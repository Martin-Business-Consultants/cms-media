# frozen_string_literal: true

require "rails_helper"

RSpec.describe Asset::Uploadable do
  def file(name) = {io: StringIO.new("PNG"), filename: name, content_type: "image/png"}

  it "uploads several files into a folder under one event, counting the saved ones" do
    assets = Asset.upload([file("a.png"), file("b.png")], folder: "/brand")

    expect(assets).to all(be_persisted)
    expect(Asset.pluck(:folder)).to eq(%w[/brand /brand])
    expect(AuditLog.last).to have_attributes(action: "assets.uploaded", metadata: {"folder" => "/brand", "count" => 2})
  end

  it "keeps a file that won't save out of the count, with its errors" do
    assets = Asset.upload([file("a.png")], folder: "no-slash")

    expect(assets.first).not_to be_persisted
    expect(assets.first.errors[:folder]).to be_present
    expect(AuditLog.where(action: "assets.uploaded")).to be_empty
  end

  it "uploads one through the API, raising on anything invalid" do
    asset = Asset.upload!(file("logo.png"), name: "Logo", folder: "/", alt: nil)

    expect(asset).to have_attributes(name: "Logo", focal_x: 0.5, filename: "logo.png")
    expect(AuditLog.last).to have_attributes(action: "assets.uploaded", metadata: {"folder" => "/", "count" => 1})
    expect { Asset.upload!(file("x.png"), folder: "bad") }.to raise_error(ActiveRecord::RecordInvalid)
  end
end
