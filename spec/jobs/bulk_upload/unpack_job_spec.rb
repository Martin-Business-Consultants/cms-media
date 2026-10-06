# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkUpload::UnpackJob do
  it "unpacks the upload it names" do
    bulk_upload = BulkUpload.create!(folder: "/", status: "pending")
    allow(BulkUpload).to receive(:find).with(bulk_upload.id).and_return(bulk_upload)
    allow(bulk_upload).to receive(:unpack_now)

    described_class.perform_now(bulk_upload.id, tenant: "old")

    expect(bulk_upload).to have_received(:unpack_now)
  end

  it "still runs jobs queued under the old name" do
    expect(BulkUploadJob.superclass).to eq(described_class)
  end
end
