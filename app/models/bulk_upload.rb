# frozen_string_literal: true

# Tracks a user-initiated bulk import of an archive (zip) of images. The
# archive itself is held as an Active Storage attachment until the job
# finishes, then purged. Per-file outcomes are recorded in `errors_log` so
# the UI can show "12 succeeded, 1 failed" with reasons. Unpacking is
# BulkUpload::Unpackable, run in the background (BulkUpload::UnpackJob).
class BulkUpload < ApplicationRecord
  include Unpackable

  STATUSES = %w[pending processing succeeded partial failed].freeze

  has_one_attached :archive

  validates :status, inclusion: {in: STATUSES}
  validates :folder, presence: true, format: {with: Asset::FOLDER_FORMAT}

  scope :recent, -> { order(created_at: :desc) }

  # A zip of images to unpack into `folder`, queued straight away.
  def self.start(archive, folder:, user: Current.user)
    bulk_upload = new(folder: folder, status: "pending", user_id: user&.id)
    bulk_upload.archive.attach(archive)
    bulk_upload.save!
    bulk_upload.unpack_later
    bulk_upload
  end

  def track_queued
    Event.record("assets.bulk_upload_queued", target: self, folder: folder)
  end

  def progress
    return 0.0 if total.zero?

    (processed.to_f / total * 100).round(1)
  end

  def finished?
    %w[succeeded partial failed].include?(status)
  end

  def record_failure!(filename:, message:)
    self.errors_log = (errors_log || []) + [{filename: filename, message: message}]
    self.failed = failed + 1
    save!(validate: false)
  end
end
