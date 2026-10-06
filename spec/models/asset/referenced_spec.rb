# frozen_string_literal: true

require "rails_helper"

RSpec.describe Asset::Referenced do
  let(:asset) { Asset.create!(folder: "/", file: {io: StringIO.new("PNG"), filename: "logo.png", content_type: "image/png"}) }

  it "names the content that uses it, and forgets it when deleted for good" do
    global = Global.create!(slug: "footer", name: "Footer",
      schema: {"fields" => [{"name" => "logo_id", "type" => "asset"}]}, data: {"logo_id" => asset.id.to_s})

    expect(asset.referencing_records).to eq([global])

    asset.destroy_permanently!
    expect(ContentReference.where(ref_type: "asset")).to be_empty
  end
end
