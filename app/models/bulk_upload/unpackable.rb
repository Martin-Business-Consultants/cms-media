# frozen_string_literal: true

require "image_processing/vips"
require "zip"

# Unpacking a bulk upload: walks the zip entry by entry, decodes each image
# (libvips reads HEIC/HEIF/AVIF natively when libheif is available), encodes
# it as WebP, and creates an Asset per file in the upload's folder.
#
# An archive is untrusted, so nothing in it is taken at its word: each entry
# is streamed to a tempfile one at a time, counting the bytes it actually
# decompresses to (never its declared size), and stops at MAX_ENTRY_BYTES;
# the whole archive stops at MAX_TOTAL_BYTES and MAX_ENTRIES images, and an
# image whose header claims more than MAX_PIXELS is refused before it's
# decoded. Only the entry's base name is used, so a path in it ("../x.png")
# goes nowhere, and an archive inside the archive isn't an image, so it's
# skipped.
#
# Per-file failures are non-fatal: they're recorded in `errors_log` and the
# walk goes on. The final status is `succeeded`, `partial` or `failed`
# depending on the failure count, and a failure of the whole run marks the
# upload failed and raises.
module BulkUpload::Unpackable
  extend ActiveSupport::Concern

  # Skip OS junk + macOS sidecar files; non-image files; obvious garbage.
  SKIP_NAME_RE = %r{(\A__MACOSX/|/\._|\A\._|\A\.DS_Store\z|/\.DS_Store\z|\AThumbs\.db\z)}
  IMAGE_EXT_RE = /\.(?:heic|heif|avif|jpe?g|png|gif|webp|tiff?|bmp)\z/i

  WEBP_QUALITY      = 85
  MAX_ENTRIES       = 2_000
  MAX_ENTRY_BYTES   = 50.megabytes
  MAX_TOTAL_BYTES   = 2.gigabytes
  MAX_PIXELS        = 100_000_000 # 10,000 × 10,000
  COPY_CHUNK        = 64.kilobytes

  # An entry or archive past a limit above.
  class TooLarge < StandardError; end
  PROGRESS_FLUSH_AT = 5  # update DB every 5 files; cheap heartbeat for the UI

  def unpack_later
    BulkUpload::UnpackJob.perform_later(id)
  end

  def unpack_now
    update!(status: "processing")
    unpack
  rescue StandardError => e
    Rails.logger.error("[BulkUpload] #{e.class}: #{e.message}")
    self.class.where(id: id).update_all(status: "failed", updated_at: Time.current)
    raise
  end

  private

  def unpack
    raise "archive not attached" unless archive&.attached?

    pending_increment = 0
    flush = lambda do
      next if pending_increment.zero?
      reload
      self.processed += pending_increment
      save!(validate: false)
      pending_increment = 0
    end

    @unpacked_bytes = 0
    archive.open(tmpdir: Dir.tmpdir) do |zip_file|
      with_zip(zip_file.path) do |entries|
        update!(total: entries.size)

        entries.each do |entry|
          begin
            handled = handle_entry(entry)
            if handled == :skipped
              increment!(:skipped)
            elsif handled == :ok
              increment!(:succeeded)
            end
          rescue TooLarge => e
            record_failure!(filename: entry.name, message: e.message)
            # Past the archive's total, every entry left would be refused too.
            raise if @unpacked_bytes > MAX_TOTAL_BYTES
          rescue StandardError => e
            record_failure!(filename: entry.name, message: "#{e.class}: #{e.message[0, 200]}")
          ensure
            pending_increment += 1
            flush.call if pending_increment >= PROGRESS_FLUSH_AT
          end
        end
      end
    end

    flush.call
    reload
    self.status = if failed.zero? && succeeded.positive?
      "succeeded"
    elsif succeeded.positive?
      "partial"
    else
      "failed"
    end
    save!

    # Archive isn't useful after a successful run — purge to free storage.
    archive.purge_later if status == "succeeded"
  end


  # The zip's image entries (junk and non-image files skipped), counted
  # before any is read so `total` is right from the start. They're read one
  # at a time, while the zip is open, by `handle_entry`.
  def with_zip(path)
    Zip::File.open(path) do |zip|
      entries = zip.entries.select { |e| e.file? && !e.name.match?(SKIP_NAME_RE) && e.name.match?(IMAGE_EXT_RE) }
      raise TooLarge, "The archive has #{entries.size} images; the limit is #{MAX_ENTRIES}." if entries.size > MAX_ENTRIES

      yield entries
    end
  end

  def handle_entry(entry)
    extract(entry) do |src|
      next :skipped if src.size.zero?

      base = File.basename(entry.name, File.extname(entry.name))
      safe_base = sanitize_basename(base)
      webp_io = convert_to_webp(src.path)
      asset = Asset.new(name: safe_base.presence || "(image)", folder: folder)
      asset.file.attach(io: webp_io, filename: "#{safe_base}.webp", content_type: "image/webp")
      asset.save!
      :ok
    ensure
      webp_io&.close
    end
  end

  # Streams one entry into a tempfile, counting what it decompresses to, and
  # yields the tempfile. Raises TooLarge past MAX_ENTRY_BYTES, or once the
  # archive as a whole passes MAX_TOTAL_BYTES.
  def extract(entry)
    src = Tempfile.new(["bulk-src-", File.extname(entry.name).presence || ".bin"], binmode: true)
    written = 0
    entry.get_input_stream do |input|
      while (chunk = input.read(COPY_CHUNK))
        written += chunk.bytesize
        @unpacked_bytes += chunk.bytesize
        raise TooLarge, "Larger than #{MAX_ENTRY_BYTES / 1.megabyte} MB unpacked." if written > MAX_ENTRY_BYTES
        raise TooLarge, "The archive unpacks to more than #{MAX_TOTAL_BYTES / 1.gigabyte} GB." if @unpacked_bytes > MAX_TOTAL_BYTES

        src.write(chunk)
      end
    end
    src.flush
    yield src
  ensure
    src&.close
    src&.unlink
  end

  # Convert an image file (any format libvips supports — HEIC, HEIF, AVIF,
  # JPEG, PNG, GIF, TIFF, BMP) into a WebP file. Strips EXIF. The header is
  # read first, so an image claiming more than MAX_PIXELS is never decoded.
  def convert_to_webp(path)
    header = Vips::Image.new_from_file(path)
    if header.width * header.height > MAX_PIXELS
      raise TooLarge, "#{header.width} × #{header.height} pixels; the limit is #{MAX_PIXELS / 1_000_000} megapixels."
    end

    out_path = ImageProcessing::Vips
      .source(path)
      .convert("webp")
      .saver(quality: WEBP_QUALITY, strip: true)
      .call

    File.open(out_path, "rb")
  end

  def sanitize_basename(name)
    # Zip entry names come back ASCII-8BIT; force UTF-8 before normalizing
    # to avoid Encoding::CompatibilityError on accented filenames.
    s = name.to_s.dup.force_encoding("UTF-8").scrub("?")
    s = (s.unicode_normalize(:nfkd) rescue s)
    s.encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .gsub(/[^\w\-]+/, "-")
      .gsub(/-+/, "-")
      .gsub(/\A-+|-+\z/, "")
      .downcase[0, 80]
  end
end
