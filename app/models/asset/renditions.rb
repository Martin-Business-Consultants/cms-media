# frozen_string_literal: true

# The URLs an asset is served at: the original, a thumbnail, a responsive
# srcset and a focal-point crop. Raster images get resized variants (Active
# Storage, generated on first request); anything else is served as uploaded.
module Asset::Renditions
  extend ActiveSupport::Concern

  # Default presets for responsive sources. Match common CSS breakpoints
  # plus a 4K row for hero/landscape art. The Astro frontend can query
  # `Asset#srcset` and emit a single <img srcset="..."> tag.
  RESPONSIVE_WIDTHS = [320, 640, 1024, 1600, 1920, 3840].freeze

  # Raster images can be resized into variants; SVG is vector (libvips can't
  # variant it and raises), so it's served as-is. Anything non-image likewise
  # has nothing to variant.
  def variantable?
    file.attached? && content_type.to_s.start_with?("image/") && content_type.to_s != "image/svg+xml"
  end

  def url
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_path(file, only_path: true)
  end

  # Lazy-generated, on-disk-cached resize for image-content thumbnails (file
  # manager grid, asset picker). Variants are computed on first request and
  # served from Active Storage's cache thereafter. Non-images fall back to the
  # original URL since we can't variant them.
  def thumb_url(size = 256)
    return nil unless file.attached?
    return url unless variantable?

    Rails.application.routes.url_helpers.rails_representation_path(
      file.variant(resize_to_limit: [size, size]),
      only_path: true
    )
  end

  # Width-keyed variant URLs the Astro frontend (or any consumer) can
  # turn into a `srcset` attribute. Each entry: { width, url, descriptor }.
  # Non-images return an empty array — there's nothing to variant.
  def srcset(widths: RESPONSIVE_WIDTHS)
    return [] unless variantable?

    widths.map { |w|
      {
        width:      w,
        descriptor: "#{w}w",
        url:        Rails.application.routes.url_helpers.rails_representation_path(
          file.variant(resize_to_limit: [w, w * 4]),
          only_path: true
        )
      }
    }
  end

  # Art-directed crop honoring the focal point. Width / height in pixels;
  # the focal_x / focal_y coordinates determine which part of the image
  # survives the crop.
  def crop_variant(width, height)
    return nil unless variantable?

    file.variant(
      resize_to_fill: [width, height, {gravity: focal_gravity}]
    )
  end

  # Translates the focal_x / focal_y floats into ImageMagick / libvips
  # gravity values via simple thirds. Avoids leaking the underlying
  # variant processor's API to callers.
  def focal_gravity
    horizontal = case focal_x
    when ..0.33 then "West"
    when ..0.66 then ""
    else             "East"
    end
    vertical = case focal_y
    when ..0.33 then "North"
    when ..0.66 then ""
    else             "South"
    end

    coord = "#{vertical}#{horizontal}"
    coord.empty? ? "Center" : coord
  end
end
