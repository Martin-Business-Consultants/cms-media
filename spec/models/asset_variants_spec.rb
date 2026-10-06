# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Asset variants" do
  describe "focal_gravity" do
    it "maps thirds to ImageMagick gravity values" do
      a = Asset.new(focal_x: 0.5, focal_y: 0.5)
      expect(a.focal_gravity).to eq("Center")

      a = Asset.new(focal_x: 0.0, focal_y: 0.0)
      expect(a.focal_gravity).to eq("NorthWest")

      a = Asset.new(focal_x: 1.0, focal_y: 1.0)
      expect(a.focal_gravity).to eq("SouthEast")

      a = Asset.new(focal_x: 0.5, focal_y: 0.0)
      expect(a.focal_gravity).to eq("North")
    end
  end

  describe "validations" do
    it "clamps focal_x / focal_y to [0, 1]" do
      a = Asset.new(focal_x: 5.0, focal_y: -1.0, folder: "/")
      a.valid?
      expect(a.focal_x).to eq(1.0)
      expect(a.focal_y).to eq(0.0)
    end
  end

  describe "srcset" do
    it "is empty for non-image assets" do
      a = Asset.new
      expect(a.srcset).to eq([])
    end
  end
end
