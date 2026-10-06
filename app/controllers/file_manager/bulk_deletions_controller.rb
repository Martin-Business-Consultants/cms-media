# frozen_string_literal: true

# Sending the files ticked in the file manager to the trash.
class FileManager::BulkDeletionsController < ApplicationController
  include FileManagerScoped

  requires_capability "assets:delete", only: :create

  def create
    assets = ticked_assets.to_a

    if assets.empty?
      back_to_folder(alert: "Tick the files to delete first.")
    else
      Asset.trash_all(assets)
      back_to_folder(notice: "#{assets.size} #{"file".pluralize(assets.size)} moved to the trash.")
    end
  end
end
