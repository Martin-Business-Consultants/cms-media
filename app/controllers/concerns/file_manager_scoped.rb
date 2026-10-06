# frozen_string_literal: true

# For the file manager's actions: where to go back to, and the folder a
# request names (?folder= or the asset's own), normalized.
module FileManagerScoped
  extend ActiveSupport::Concern

  private

  def back_to_folder(folder = params[:folder], **flash)
    folder = nil if folder.blank? || folder == "/"
    redirect_to file_manager_path(folder: folder, view: params[:view].presence), **flash
  end

  # The ticked assets of a bulk action (ids[] from the table's checkboxes).
  def ticked_assets
    Asset.where(id: Array(params[:ids]).compact_blank)
  end
end
