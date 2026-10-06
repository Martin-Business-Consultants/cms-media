# frozen_string_literal: true

require "rails_helper"

# An asset as the API hands it to a site: absolute URLs on the CMS's own host
# (APP_HOST, "example.com" in test), size, and renditions.
RSpec.describe Asset::Delivery do
  def upload(path, type)
    Asset.upload!(Rack::Test::UploadedFile.new(Rails.root.join(path), type), folder: "/")
  end

  it "gives an image absolute URLs on the CMS's host, its size and its renditions" do
    Setting.set("general", site_base_url: "https://www.acme.test")
    delivery = upload("public/icon.png", "image/png").reload.delivery

    expect(delivery["url"]).to start_with("http://example.com/rails/active_storage/blobs/")
    expect(delivery["original"]).to eq(delivery["url"])
    expect(delivery).to include("filename" => "icon.png", "content_type" => "image/png")
    expect(delivery["width"]).to be_a(Integer).and be_positive
    expect(delivery["height"]).to be_a(Integer).and be_positive
    expect(delivery["thumb_url"]).to start_with("http://example.com/")
    expect(delivery["srcset"]).to all(include(url: start_with("http://example.com/")))

    if ApplicationHelper.variants_supported?
      expect(delivery["variants"].keys).to eq(%w[w640 w1280 w1920])
      expect(delivery["variants"].values).to all(start_with("http://example.com/rails/active_storage/representations/"))
    else
      expect(delivery["variants"]).to eq({})
    end
  end

  it "has no renditions for an SVG, which is served as it is" do
    delivery = upload("public/icon.svg", "image/svg+xml").reload.delivery

    expect(delivery["url"]).to start_with("http://example.com/")
    expect(delivery["variants"]).to eq({})
    expect(delivery["thumb_url"]).to eq(delivery["url"])
  end

  it "gives a file that isn't an image no size" do
    asset = Asset.upload!(Rack::Test::UploadedFile.new(StringIO.new("%PDF-1.4"), "application/pdf", original_filename: "menu.pdf"), folder: "/")

    expect(asset.delivery).to include("width" => nil, "height" => nil, "filename" => "menu.pdf")
    expect(asset.delivery).not_to have_key("variants")
  end
end
