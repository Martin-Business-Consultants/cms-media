# frozen_string_literal: true

# The media library's filters, as WordPress's are: by kind of file (images,
# video, audio, documents — anything else) and by the month it was added.
module Asset::Filterable
  extend ActiveSupport::Concern

  MONTH_FORMAT = /\A\d{4}-(0[1-9]|1[0-2])\z/

  KINDS = {"images" => "Images", "video" => "Video", "audio" => "Audio", "documents" => "Documents"}.freeze
  MEDIA_PREFIXES = {"images" => "image/", "video" => "video/", "audio" => "audio/"}.freeze

  included do
    scope :of_kind, ->(kind) {
      blobs = joins(file_attachment: :blob)
      if (prefix = MEDIA_PREFIXES[kind])
        blobs.where("active_storage_blobs.content_type LIKE ?", "#{prefix}%")
      else
        MEDIA_PREFIXES.values.reduce(blobs) { |scope, other| scope.where.not("active_storage_blobs.content_type LIKE ?", "#{other}%") }
      end
    }

    # "2026-09": added that month (in UTC, as `months` reads them).
    scope :added_in, ->(month) {
      year, number = month.to_s.split("-").map(&:to_i)
      start = Time.utc(year, number)
      where(created_at: start...(start + 1.month))
    }
  end

  class_methods do
    # The months anything was added in, newest first, as "2026-09".
    def months
      distinct.pluck(Arel.sql("strftime('%Y-%m', assets.created_at)")).compact.sort.reverse
    end
  end
end
