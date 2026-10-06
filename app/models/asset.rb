# frozen_string_literal: true

# An uploadable asset (image, file). Wraps an Active Storage attachment with
# a stable ID that gets stored as the value of `:asset` block fields.
#
# What an asset does lives in the concerns under app/models/asset/; this file
# keeps the attachment, the validations (in the order their errors are
# reported) and what it's called.
class Asset < ApplicationRecord
  include SoftDeletable
  include Eventable
  # One per line: callbacks and associations register in include order.
  include Uploadable
  include Movable
  include Trashable
  include Referenced
  include Renditions
  include Delivery
  include Filterable

  # `folder` is a virtual filesystem path used by the file manager UI.
  # Always starts with "/", never ends with "/" except for root ("/").
  # Permissive on casing — the file manager UI lets users name folders freely.
  FOLDER_FORMAT = %r{\A/(?:[A-Za-z0-9][A-Za-z0-9_\- ]*(?:/[A-Za-z0-9][A-Za-z0-9_\- ]*)*)?\z}

  has_one_attached :file

  validates :file, presence: true
  validates :folder, presence: true, format: {with: FOLDER_FORMAT}
  validates :focal_x, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1}
  validates :focal_y, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 1}

  before_validation :clamp_focal_point

  normalizes :folder, with: ->(v) { v.to_s.strip.presence || "/" }

  # By file name or display name, as the file manager's search and
  # GET /api/assets?q= find them.
  scope :matching, ->(query) {
    pattern = "%#{query}%"
    joins(file_attachment: :blob).where("active_storage_blobs.filename LIKE ? OR assets.name LIKE ?", pattern, pattern).distinct
  }

  # Images only — what a logo or favicon picker offers.
  scope :images, -> { joins(file_attachment: :blob).where("active_storage_blobs.content_type LIKE ?", "image/%") }

  # What the file manager shows it as: its display name, else its file name.
  def title = name.presence || filename

  def image? = content_type.to_s.start_with?("image/")

  def track_update = track_event(:updated, folder: folder)

  def filename
    file.attached? ? file.filename.to_s : nil
  end

  def content_type
    file.attached? ? file.content_type : nil
  end

  def byte_size
    file.attached? ? file.byte_size : 0
  end

  private

  def clamp_focal_point
    self.focal_x = focal_x.to_f.clamp(0.0, 1.0) unless focal_x.nil?
    self.focal_y = focal_y.to_f.clamp(0.0, 1.0) unless focal_y.nil?
  end
end
