# frozen_string_literal: true

require "rails_helper"

RSpec.describe AssetFolders do
  before { Setting.delete_key("assets") }

  def make(folder) = Asset.create!(folder: folder, file: {io: StringIO.new("PNG"), filename: "a.png", content_type: "image/png"})

  it "records creating a folder, by its normalized path" do
    expect(described_class.create("campaigns/ fall ")).to eq("/campaigns/fall")
    expect(AuditLog.last).to have_attributes(action: "asset_folder.created", metadata: {"path" => "/campaigns/fall"})
  end

  it "records a rename by its normalized paths" do
    make("/brand/logos")

    expect(described_class.rename("brand", "/identity")).to eq(1)
    expect(Asset.pluck(:folder)).to eq(%w[/identity/logos])
    expect(AuditLog.last).to have_attributes(action: "asset_folder.renamed", metadata: {"from" => "/brand", "to" => "/identity", "moved" => 1})
  end

  it "records a delete by its normalized path" do
    make("/old")

    expect(described_class.delete("old/")).to eq(1)
    expect(AuditLog.last).to have_attributes(action: "asset_folder.deleted", metadata: {"path" => "/old", "discarded" => 1})
  end

  it "records nothing it refuses" do
    expect { described_class.rename("/", "/x") }.to raise_error(described_class::InvalidPath)
    expect(AuditLog.count).to eq(0)
  end
end
