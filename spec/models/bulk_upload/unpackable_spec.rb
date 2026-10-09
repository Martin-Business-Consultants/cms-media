# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe BulkUpload::Unpackable do
  include ActiveJob::TestHelper

  PNG_1PX = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")

  def archive(entries)
    zip = Zip::OutputStream.write_buffer { |out| entries.each { |name, bytes| out.put_next_entry(name); out.write(bytes) } }
    Rack::Test::UploadedFile.new(StringIO.new(zip.string), "application/zip", original_filename: "pics.zip")
  end

  it "queues itself when started" do
    bulk_upload = BulkUpload.start(archive("a.png" => PNG_1PX), folder: "/zips", user: nil)

    expect(bulk_upload).to have_attributes(status: "pending", folder: "/zips")
    expect(BulkUpload::UnpackJob).to have_been_enqueued.with(bulk_upload.id)
  end

  it "turns each image into a WebP asset and skips what isn't one" do
    bulk_upload = BulkUpload.start(archive("One.png" => PNG_1PX, "__MACOSX/._x.png" => "x", "notes.txt" => "hi"), folder: "/zips", user: nil)

    bulk_upload.unpack_now

    expect(bulk_upload.reload).to have_attributes(status: "succeeded", total: 1, processed: 1, succeeded: 1, failed: 0)
    expect(Asset.where(folder: "/zips").map { [it.name, it.filename, it.content_type] }).to eq([["one", "one.webp", "image/webp"]])
  end

  it "records a file it can't decode and goes on" do
    bulk_upload = BulkUpload.start(archive("broken.png" => "not an image", "ok.png" => PNG_1PX), folder: "/", user: nil)

    bulk_upload.unpack_now

    expect(bulk_upload.reload).to have_attributes(status: "partial", succeeded: 1, failed: 1)
    expect(bulk_upload.errors_log.first["filename"]).to eq("broken.png")
  end

  describe "an untrusted archive" do
    it "refuses an image that unpacks past MAX_ENTRY_BYTES, counting what it decompresses to, and goes on" do
      stub_const("BulkUpload::Unpackable::MAX_ENTRY_BYTES", 1_000)
      bulk_upload = BulkUpload.start(archive("big.png" => PNG_1PX + ("\0" * 5_000), "ok.png" => PNG_1PX), folder: "/", user: nil)

      bulk_upload.unpack_now

      expect(bulk_upload.reload).to have_attributes(status: "partial", succeeded: 1, failed: 1)
      expect(bulk_upload.errors_log.first).to include("filename" => "big.png", "message" => a_string_including("unpacked"))
    end

    it "stops the whole upload once the archive unpacks past MAX_TOTAL_BYTES" do
      stub_const("BulkUpload::Unpackable::MAX_TOTAL_BYTES", PNG_1PX.bytesize + 10)
      bulk_upload = BulkUpload.start(archive("a.png" => PNG_1PX, "b.png" => PNG_1PX, "c.png" => PNG_1PX), folder: "/", user: nil)

      expect { bulk_upload.unpack_now }.to raise_error(BulkUpload::Unpackable::TooLarge, /unpacks to more than/)
      expect(bulk_upload.reload.status).to eq("failed")
      expect(Asset.count).to eq(1)
    end

    it "refuses an archive with more than MAX_ENTRIES images before reading any" do
      stub_const("BulkUpload::Unpackable::MAX_ENTRIES", 2)
      bulk_upload = BulkUpload.start(archive("a.png" => PNG_1PX, "b.png" => PNG_1PX, "c.png" => PNG_1PX), folder: "/", user: nil)

      expect { bulk_upload.unpack_now }.to raise_error(BulkUpload::Unpackable::TooLarge, /3 images; the limit is 2/)
      expect(bulk_upload.reload.status).to eq("failed")
      expect(Asset.count).to eq(0)
    end

    it "refuses an image whose header claims more than MAX_PIXELS, without decoding it" do
      stub_const("BulkUpload::Unpackable::MAX_PIXELS", 0)
      bulk_upload = BulkUpload.start(archive("a.png" => PNG_1PX), folder: "/", user: nil)

      bulk_upload.unpack_now

      expect(bulk_upload.reload).to have_attributes(status: "failed", failed: 1)
      expect(bulk_upload.errors_log.first["message"]).to include("pixels")
    end

    it "uses only an entry's base name, so a path in it goes nowhere" do
      bulk_upload = BulkUpload.start(archive("../../etc/Evil.png" => PNG_1PX), folder: "/safe", user: nil)

      bulk_upload.unpack_now

      expect(Asset.pluck(:name, :folder)).to eq([["evil", "/safe"]])
    end
  end

  it "marks the whole upload failed when the run itself fails" do
    bulk_upload = BulkUpload.create!(folder: "/", status: "pending")

    expect { bulk_upload.unpack_now }.to raise_error(RuntimeError, /archive not attached/)
    expect(bulk_upload.reload.status).to eq("failed")
  end
end
