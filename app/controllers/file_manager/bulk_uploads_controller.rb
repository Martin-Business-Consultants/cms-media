# frozen_string_literal: true

# A zip of images unpacked into a folder in the background
# (BulkUpload::Unpackable: each image becomes a WebP asset), and the page that
# follows its progress.
class FileManager::BulkUploadsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:write", only: [:create, :show]

  def create
    folder = AssetFolders.normalize(params[:folder])

    if params[:archive].blank?
      back_to_folder(folder, alert: "Choose a .zip of images.")
    else
      bulk_upload = BulkUpload.start(params[:archive], folder: folder)
      bulk_upload.track_queued

      redirect_to file_manager_bulk_upload_path(bulk_upload)
    end
  rescue AssetFolders::InvalidPath => e
    back_to_folder(alert: e.message)
  end

  def show
    @bulk_upload = BulkUpload.find(params[:id])
  end
end
