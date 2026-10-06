# frozen_string_literal: true

# An asset as the API hands it to a site (/api/assets, ?resolve=assets):
# absolute URLs on the CMS's own host — Site.url_options, from APP_HOST and
# APP_PROTOCOL, never the public site's address — so a site on another
# domain (an Astro build, a Worker) can fetch them as remote images, plus an
# image's width and height and a few width-limited renditions.
#
#   asset.delivery
#   # => {"url" => "https://cms.acme.com/rails/active_storage/blobs/…/logo.png",
#   #     "original" => (the same), "width" => 1200, "height" => 630,
#   #     "variants" => {"w640" => "https://…", "w1280" => "https://…", "w1920" => "https://…"}, …}
#
# The admin's own pages keep using #url and #thumb_url, which are paths.
module Asset::Delivery
  extend ActiveSupport::Concern

  # The renditions every image offers, by width; height follows the image.
  DELIVERY_WIDTHS = [640, 1280, 1920].freeze

  def absolute_url
    blob_url(file) if file.attached?
  end

  # From the blob's analysis, made the first time they're asked for if Active
  # Storage's background analysis hasn't run yet; nil for a file that isn't an
  # image, or one the analyzer can't read (an SVG may have none).
  def width = measurements["width"]

  def height = measurements["height"]

  # {"w640" => url, …}: empty for an SVG, a non-image, or an install whose
  # libvips can't make variants (ApplicationHelper.variants_supported?).
  def variants
    return {} unless variantable? && ApplicationHelper.variants_supported?

    DELIVERY_WIDTHS.to_h { |w| ["w#{w}", representation_url(file.variant(resize_to_limit: [w, nil]))] }
  end

  def delivery
    {
      "id" => id, "url" => absolute_url, "original" => absolute_url,
      "filename" => filename, "content_type" => content_type, "byte_size" => byte_size,
      "width" => width, "height" => height, "alt" => alt, "folder" => folder
    }.tap do |summary|
      next unless image?

      summary["variants"] = variants
      summary["thumb_url"] = variantable? && ApplicationHelper.variants_supported? ? representation_url(file.variant(resize_to_limit: [256, 256])) : absolute_url
      summary["srcset"] = srcset.map { it.merge(url: absolute(it[:url])) }
      summary["focal_x"] = focal_x
      summary["focal_y"] = focal_y
    end
  end

  private

  def measurements
    @measurements ||= begin
      return {} unless image? && file.attached?

      file.analyze unless file.analyzed?
      file.metadata
    rescue StandardError => e
      Rails.logger.warn("[Asset] couldn't measure asset #{id}: #{e.class}: #{e.message}")
      {}
    end
  end

  def blob_url(attachment) = Rails.application.routes.url_helpers.rails_blob_url(attachment, **Site.url_options)

  def representation_url(variant) = Rails.application.routes.url_helpers.rails_representation_url(variant, **Site.url_options)

  def absolute(path)
    options = Site.url_options
    "#{options[:protocol]}://#{options[:host]}#{":#{options[:port]}" if options[:port]}#{path}"
  end
end
