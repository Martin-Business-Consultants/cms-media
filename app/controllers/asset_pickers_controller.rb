# frozen_string_literal: true

# The picker a content form's asset fields open: the file manager's library
# in a turbo frame — search, folders, and uploading straight into it. Picking
# an asset is done in the browser (asset-picker controller); the field stores
# the asset's id, as it always has.
class AssetPickersController < ApplicationController
  requires_capability "assets:read",  only: :show
  requires_capability "assets:write", only: :create

  PER_PAGE = 60

  def show
    load_library
  end

  # files[]: signed ids from direct uploads (or the files themselves).
  def create
    @folder = normalized_folder
    files = Array(params[:files]).compact_blank
    @uploaded = Asset.upload(files, folder: @folder)
    saved = @uploaded.select(&:persisted?)
    @upload_errors = (@uploaded - saved).map { |asset| "#{asset.file.filename}: #{asset.errors.full_messages.to_sentence}" }
    load_library
    render :show, status: (@upload_errors.any? ? :unprocessable_content : :ok)
  rescue AssetFolders::InvalidPath => e
    @upload_errors = [e.message]
    load_library
    render :show, status: :unprocessable_content
  end

  private

  def load_library
    @query = params[:q].to_s.strip
    @folder ||= normalized_folder
    @folders = (["/"] + AssetFolders.all(Asset.distinct.pluck(:folder))).uniq
    assets = Asset.with_attached_file.order(created_at: :desc)
    assets = @query.present? ? assets.matching(@query) : assets.where(folder: @folder)
    @assets = assets.limit(PER_PAGE)
  end

  def normalized_folder
    AssetFolders.normalize(params[:folder])
  rescue AssetFolders::InvalidPath
    "/"
  end
end
