# frozen_string_literal: true

module FileManagerHelper
  # A preview for the file manager: a resized image when the image can be
  # resized here, the original when it can't (SVG, or no libvips), and a
  # paperclip for anything that isn't an image.
  def asset_thumbnail(asset, size:)
    if asset.image?
      source = asset.variantable? && ApplicationHelper.variants_supported? ? asset.thumb_url(size) : asset.url
      image_tag source, alt: asset.alt.to_s, loading: "lazy", decoding: "async"
    else
      icon_tag "attachment", class: "file-manager__file-icon"
    end
  end
end
