# frozen_string_literal: true

require "image_processing/vips"
require "zip"

# Unpacking a bulk upload: walks the zip entry by entry, decodes each image
# (libvips reads HEIC/HEIF/AVIF natively when libheif is available), encodes
# it as WebP, and creates an Asset per file in the upload's folder.
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


  # Walk the zip entries, returning only the ones that look like images we
  # should attempt (skipping junk + non-image files). We collect first so the
  # `total` is correct before we start iterating.
  def with_zip(path)
    entries = []
    Zip::File.open(path) do |zip|
      zip.each do |e|
        next unless e.file?
        next if e.name.match?(SKIP_NAME_RE)
        next unless e.name.match?(IMAGE_EXT_RE)
        entries << ZipEntry.new(e.name, e.size, e.get_input_stream.read)
      end
    end
    yield entries
  end

  ZipEntry = Struct.new(:name, :size, :bytes)

  def handle_entry(entry)
    return :skipped if entry.bytes.empty?

    base = File.basename(entry.name, File.extname(entry.name))
    safe_base = sanitize_basename(base)
    target_filename = "#{safe_base}.webp"

    webp_io = convert_to_webp(entry.bytes, entry.name)
    asset = Asset.new(
      name:   safe_base.presence || "(image)",
      folder: folder
    )
    asset.file.attach(
      io:           webp_io,
      filename:     target_filename,
      content_type: "image/webp"
    )
    asset.save!
    :ok
  ensure
    webp_io&.close
  end

  # Convert an in-memory image (any format libvips supports — HEIC, HEIF,
  # AVIF, JPEG, PNG, GIF, TIFF, BMP) into a WebP Tempfile. Strips EXIF.
  def convert_to_webp(bytes, source_filename)
    src = Tempfile.new(["bulk-src-", File.extname(source_filename).presence || ".bin"], binmode: true)
    src.write(bytes)
    src.flush
    src.rewind

    out_path = ImageProcessing::Vips
      .source(src.path)
      .convert("webp")
      .saver(quality: WEBP_QUALITY, strip: true)
      .call

    File.open(out_path, "rb")
  ensure
    src&.close
    src&.unlink
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
