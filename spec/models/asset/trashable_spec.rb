# frozen_string_literal: true

require "rails_helper"

RSpec.describe Asset::Trashable do
  def make(name) = Asset.create!(folder: "/", file: {io: StringIO.new("PNG"), filename: name, content_type: "image/png"})

  it "trashes an asset and records it by name" do
    asset = make("logo.png")

    asset.trash

    expect(Asset.with_discarded.find(asset.id)).to be_discarded
    expect(AuditLog.last).to have_attributes(action: "asset.deleted", target_id: asset.id, metadata: {"name" => "logo.png"})
  end

  it "trashes a set under one event naming them" do
    Asset.trash_all([make("a.png"), make("b.png")])

    expect(Asset.count).to eq(0)
    expect(AuditLog.last).to have_attributes(action: "assets.bulk_deleted", metadata: {"count" => 2, "names" => %w[a.png b.png]})
  end
end
