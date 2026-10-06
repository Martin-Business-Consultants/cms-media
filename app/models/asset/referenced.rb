# frozen_string_literal: true

# Where an asset is used: the pages, entries and globals whose content points
# at it (ContentReference, kept by their Referencing concerns, which store an
# asset reference with ref_type "asset"). Deleting an asset for good removes
# those references with it.
module Asset::Referenced
  extend ActiveSupport::Concern

  included do
    before_destroy :remove_content_references
  end

  # The pages, entries and globals whose content uses this asset, each once.
  def referencing_records
    ContentReference.where(ref_type: "asset", ref_id: id.to_s).includes(:owner).filter_map(&:owner).uniq
  end

  private

  def remove_content_references
    ContentReference.where(ref_type: "asset", ref_id: id.to_s).delete_all
  end
end
