# frozen_string_literal: true

# One asset in the media library: its details (preview, what it is, where
# it's used), shown in the library's sheet or on its own page; uploading into
# a folder; saving its title, alt text, caption, description and folder; and
# sending it to the trash. The API's /api/assets is the same library for scripts.
class FileManager::AssetsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:read",   only: :show
  requires_capability "assets:write",  only: [:create, :update]
  requires_capability "assets:delete", only: :destroy

  before_action :set_asset, only: [:show, :update, :destroy]

  def show
    @folders = AssetFolders.all(Asset.distinct.pluck(:folder))
  end

  # files[]: signed ids from Active Storage direct uploads, or the files
  # themselves when the page's JavaScript didn't run.
  def create
    folder = AssetFolders.normalize(params[:folder])
    files = Array(params[:files]).compact_blank

    if files.empty?
      back_to_folder(folder, alert: "Choose one or more files to upload.")
    else
      saved, failed = Asset.upload(files, folder: folder).partition(&:persisted?)
      back_to_folder(folder, **upload_flash(saved, failed))
    end
  rescue AssetFolders::InvalidPath => e
    back_to_folder(alert: e.message)
  end

  def update
    if @asset.update(asset_params)
      @asset.track_update
      redirect_to file_manager_asset_path(@asset), notice: "Saved"
    else
      @folders = AssetFolders.all(Asset.distinct.pluck(:folder))
      render :show, status: :unprocessable_content
    end
  end

  def destroy
    @asset.trash
    back_to_folder(@asset.folder, notice: "#{@asset.title} is in the trash.")
  end

  private

  def set_asset
    @asset = Asset.with_attached_file.find(params[:id])
  end

  def asset_params
    permitted = params.require(:asset).permit(:name, :alt, :caption, :description, :folder)
    permitted[:folder] = normalized(permitted[:folder]) if permitted.key?(:folder)
    permitted
  end

  # Left as typed when it isn't a valid path, so the model's validation says so.
  def normalized(folder)
    AssetFolders.normalize(folder)
  rescue AssetFolders::InvalidPath
    folder
  end

  def upload_flash(saved, failed)
    if failed.empty?
      {notice: "Uploaded #{saved.size} #{"file".pluralize(saved.size)}."}
    else
      reasons = failed.map { |asset| "#{asset.file.filename}: #{asset.errors.full_messages.to_sentence}" }
      {alert: "Uploaded #{saved.size}; #{failed.size} failed — #{reasons.first(3).join(" · ")}"}
    end
  end
end
