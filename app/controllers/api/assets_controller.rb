# frozen_string_literal: true

# The asset library over the API: a page of assets (newest first, optionally
# searched), one asset, uploading one, editing its details, and sending it to
# the trash. The JSON is app/views/api/assets.
class Api::AssetsController < Api::BaseController
  enforce_authorization
  requires_capability "assets:read",   only: [:index, :show]
  requires_capability "assets:write",  only: [:create, :update]
  requires_capability "assets:delete", only: :destroy

  PER_PAGE_DEFAULT = 24
  PER_PAGE_MAX     = 100

  before_action :set_asset, only: [:show, :update, :destroy]

  def index
    scope = Asset.with_attached_file
    scope = scope.matching(params[:q]) if params[:q].present?

    @total = scope.count
    @page  = [params[:page].to_i, 1].max
    @per   = clamp_per(params[:per].to_i)
    @total_pages = [(@total.to_f / @per).ceil, 1].max
    @assets = scope.order(created_at: :desc).offset((@page - 1) * @per).limit(@per)
  end

  def create
    return render(json: {error: "file is required"}, status: :bad_request) unless params[:file]

    @asset = Asset.upload!(params[:file],
      name:    params[:name].presence,
      folder:  params[:folder].presence || "/",
      alt:     params[:alt].presence,
      focal_x: params[:focal_x].presence,
      focal_y: params[:focal_y].presence)
    render :show, status: :created
  end

  def show
  end

  def update
    @asset.update!(params.permit(:name, :folder, :alt, :caption, :description, :focal_x, :focal_y))
    @asset.track_update
    render :show
  end

  def destroy
    @asset.trash
    head :no_content
  end

  private

  def set_asset
    @asset = Asset.find(params[:id])
  end

  def clamp_per(raw)
    return PER_PAGE_DEFAULT if raw <= 0

    [raw, PER_PAGE_MAX].min
  end
end
