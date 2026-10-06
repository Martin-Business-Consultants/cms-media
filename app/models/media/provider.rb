# frozen_string_literal: true

# What the core's media interface (MediaLibrary) reads from this plugin:
# Cms::Plugins.provide :media hands it this module.
module Media::Provider
  module_function

  def find(id) = Asset.with_attached_file.find_by(id: id)

  def upload(file, folder:) = Asset.upload!(file, folder: folder)

  def resolve(kind, records)
    case kind.to_sym
    when :pages then Asset::Resolver.for_pages(records)
    when :entries then Asset::Resolver.for_entries(records)
    when :globals then Asset::Resolver.for_globals(records)
    end
  end

  # [every image, those used in content without alt text], for Site health.
  def images_without_alt
    images = Asset.images.to_a
    [images, images.select { it.alt.blank? && it.referencing_records.any? }]
  end
end
