# frozen_string_literal: true

# Deleting an asset puts it in the trash (SoftDeletable), where it can be
# restored for the retention window.
module Asset::Trashable
  extend ActiveSupport::Concern

  class_methods do
    # Trashes every asset and records one event naming them.
    def trash_all(assets)
      assets.each(&:discard!)
      Event.record("assets.bulk_deleted", count: assets.size, names: assets.map(&:title)) if assets.any?
      assets
    end
  end

  def trash
    discard!
    track_event(:deleted, name: title)
  end
end
