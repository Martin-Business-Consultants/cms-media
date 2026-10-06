# frozen_string_literal: true

# The media library, laid out like WordPress's: a grid of every file (or a
# list), filtered by kind, month added and folder, and searched; a file's
# details open in a sheet (FileManager::AssetsController#show). Folders are
# virtual — the `assets.folder` column is a path, and a folder exists because
# something says it does: an asset sits in it, or a person made it and it is
# still empty (remembered in Setting["assets"]; AssetFolders).
#
# ?folder= narrows to one folder ("/" is the top level; none is every
# folder), ?kind= and ?month= are the filters, ?q= searches, ?view= is cards
# or table.
class FileManagerController < ApplicationController
  requires_capability "assets:read", only: :index

  def index
    @folder = normalized_folder
    @kind = params[:kind].presence_in(Asset::Filterable::KINDS.keys)
    @month = params[:month].to_s[Asset::Filterable::MONTH_FORMAT]
    @query = params[:q].to_s.strip
    @view = params[:view].presence_in(%w[cards table]) || "cards"
    @folders = AssetFolders.all(Asset.distinct.pluck(:folder))
    @months = Asset.months
    @subfolders = @folder && @query.blank? ? AssetFolders.children(@folders, @folder) : []
    @total = assets.count
    @assets = paginate(assets)
  end

  private

  def normalized_folder
    return nil if params[:folder].blank?

    AssetFolders.normalize(params[:folder])
  rescue AssetFolders::InvalidPath
    nil
  end

  def assets
    @assets_scope ||= begin
      scope = Asset.with_attached_file.order(created_at: :desc)
      scope = scope.matching(@query) if @query.present?
      scope = scope.where(folder: @folder) if @folder
      scope = scope.of_kind(@kind) if @kind
      scope = scope.added_in(@month) if @month
      scope
    end
  end
end
