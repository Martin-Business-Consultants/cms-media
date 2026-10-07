# frozen_string_literal: true

module FileManagerHelper
  # A preview for the file manager: a resized image when the image can be
  # resized here, the original when it can't (SVG, or no libvips), and a
  # paperclip for anything that isn't an image. The image is bare; the square
  # around it (.media-thumb, file-manager.css) fits it.
  def asset_thumbnail(asset, size:)
    if asset.image?
      source = asset.variantable? && ApplicationHelper.variants_supported? ? asset.thumb_url(size) : asset.url
      image_tag source, alt: asset.alt.to_s, loading: "lazy", decoding: "async"
    elsif size >= 240
      icon_tag "attachment", class: "size-10"
    else
      icon_tag "attachment", class: "size-5"
    end
  end

  # What's under a file's name in the grid: its kind and size, "PNG · 12 KB".
  def asset_meta(asset)
    kind = File.extname(asset.filename.to_s).delete(".").presence || asset.content_type.to_s.split("/").last
    [kind&.upcase, number_to_human_size(asset.byte_size)].compact_blank.join(" · ")
  end
end
