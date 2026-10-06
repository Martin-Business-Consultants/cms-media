# frozen_string_literal: true

# Folder operations for the asset library. Folders are paths on assets, so
# "rename" moves every asset under the old path and "delete" trashes them —
# see AssetFolders, which records each. Assets themselves are at /api/assets.
class Api::AssetFoldersController < Api::BaseController
  enforce_authorization
  requires_capability "assets:write",  only: [:create, :update]
  requires_capability "assets:delete", only: :destroy

  rescue_from AssetFolders::InvalidPath do |e|
    render json: {error: e.message}, status: :unprocessable_entity
  end

  def create
    @path = AssetFolders.create(params.require(:path))
    render status: :created
  end

  def update
    from = params.require(:path)
    to = params.require(:to)
    @moved = AssetFolders.rename(from, to)
    @path = AssetFolders.normalize(to)
  end

  def destroy
    @path = params.require(:path)
    @discarded = AssetFolders.delete(@path)
  end
end
