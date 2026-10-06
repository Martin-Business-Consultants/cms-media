# frozen_string_literal: true

# Moving the files ticked in the file manager into another folder.
class FileManager::MovesController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:write", only: :create

  def create
    assets = ticked_assets
    to = AssetFolders.normalize(params[:to])

    if assets.none?
      back_to_folder(alert: "Tick the files to move first.")
    else
      Asset.move_all(assets, to: to)
      back_to_folder(to, notice: "Moved #{assets.size} #{"file".pluralize(assets.size)} to #{to}.")
    end
  rescue AssetFolders::InvalidPath => e
    back_to_folder(alert: e.message)
  end
end
