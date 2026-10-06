# frozen_string_literal: true

require "rails_helper"

RSpec.describe Asset::Movable do
  def make(name) = Asset.create!(folder: "/", file: {io: StringIO.new("PNG"), filename: name, content_type: "image/png"})

  it "moves assets into a folder under one event" do
    Asset.move_all([make("a.png"), make("b.png")], to: "/brand")

    expect(Asset.pluck(:folder)).to eq(%w[/brand /brand])
    expect(AuditLog.last).to have_attributes(action: "assets.moved", metadata: {"to" => "/brand", "count" => 2})
  end

  it "moves none when one can't go" do
    assets = [make("a.png"), make("b.png")]

    expect { Asset.move_all(assets, to: "bad") }.to raise_error(ActiveRecord::RecordInvalid)
    expect(Asset.pluck(:folder)).to eq(%w[/ /])
  end
end
