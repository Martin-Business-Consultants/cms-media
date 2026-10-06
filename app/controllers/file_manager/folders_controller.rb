# frozen_string_literal: true

# The file manager's folders (AssetFolders): making one, renaming or moving
# it with everything inside, and sending it, with its files, to the trash.
# ?path= is the folder; create takes the parent and a name.
class FileManager::FoldersController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:write",  only: [:create, :update]
  requires_capability "assets:delete", only: :destroy

  rescue_from AssetFolders::InvalidPath do |error|
    back_to_folder(params[:path].presence || params[:parent], alert: error.message)
  end

  def create
    path = AssetFolders.create(File.join(params[:parent].presence || "/", params[:name].to_s))
    back_to_folder(path, notice: "Folder #{AssetFolders.name(path)} created.")
  end

  # to: the new path; or name: a new name in the same parent.
  def update
    from = AssetFolders.normalize(params.require(:path))
    to = AssetFolders.normalize(params[:to].presence || File.join(AssetFolders.parent(from), params[:name].to_s))
    AssetFolders.rename(from, to)
    back_to_folder(to, notice: "Folder is now #{to}.")
  end

  def destroy
    path = AssetFolders.normalize(params.require(:path))
    discarded = AssetFolders.delete(path)
    back_to_folder(AssetFolders.parent(path),
      notice: "Folder #{AssetFolders.name(path)} deleted; #{discarded} #{"file".pluralize(discarded)} went to the trash.")
  end
end
