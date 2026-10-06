# frozen_string_literal: true

# A zip of images unpacked into a folder in the background
# (BulkUpload::Unpackable), and its progress. The JSON is
# app/views/api/bulk_uploads.
class Api::BulkUploadsController < Api::BaseController
  # Starting one writes assets, so it takes assets:write, and it's recorded
  # the way the file manager's upload is.
  def create
    require_capability!("assets:write")
    return render(json: {error: "archive is required"}, status: :bad_request) unless params[:archive]

    @bulk_upload = BulkUpload.start(params[:archive], folder: params[:folder].presence || "/")
    @bulk_upload.track_queued
    render :show, status: :created
  end

  def show
    @bulk_upload = BulkUpload.find(params[:id])
  end
end
