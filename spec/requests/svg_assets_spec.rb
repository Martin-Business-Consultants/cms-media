# frozen_string_literal: true

require "rails_helper"

# SVG uploads are served inline as image/svg+xml, so the consumer site can
# put them in <img> tags, but under a sandboxing CSP so one opened directly
# can't run script on the admin origin. See SvgSandbox.
RSpec.describe "Serving uploaded assets", type: :request do
  let(:svg) do
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">
        <script>alert(document.cookie)</script>
        <rect width="10" height="10" fill="red"/>
      </svg>
    SVG
  end

  def upload(name, body, content_type)
    Asset.create!(folder: "/", file: {io: StringIO.new(body), filename: name, content_type: content_type})
  end

  # Asset#url is the blobs/redirect route; it bounces to the disk service.
  def fetch(asset)
    get asset.url
    expect(response).to have_http_status(:redirect)
    get response.location
  end

  it "serves an SVG inline as image/svg+xml under a sandboxing CSP" do
    asset = upload("logo.svg", svg, "image/svg+xml")

    fetch(asset)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/svg+xml")
    expect(response.headers["content-disposition"]).to start_with("inline")
    expect(response.headers["content-security-policy"]).to eq(SvgSandbox::CONTENT_SECURITY_POLICY)
    expect(response.headers["content-security-policy"]).to include("sandbox")
    expect(response.headers["x-content-type-options"]).to eq("nosniff")
    expect(response.body).to eq(svg)
  end

  it "leaves a PNG alone" do
    asset = upload("photo.png", "PNG", "image/png")

    fetch(asset)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["content-disposition"]).to start_with("inline")
    expect(response.headers["content-security-policy"].to_s).not_to include("sandbox")
  end
end
