# frozen_string_literal: true

require "rails_helper"

RSpec.describe Asset::Resolver do
  def make_asset(name = "a-#{SecureRandom.hex(3)}.png", alt: nil)
    Asset.create!(
      folder: "/",
      alt:    alt,
      file:   {io: StringIO.new("PNG"), filename: name, content_type: "image/png"}
    )
  end

  before do
    BlockType.create!(slug: "gallery", label: "Gallery", fields: [
      {"name" => "cover", "type" => "asset"},
      {"name" => "slides", "type" => "repeater", "of" => [{"name" => "image", "type" => "asset"}]},
      {"name" => "cta", "type" => "group", "of" => [
        {"name" => "label", "type" => "string"},
        {"name" => "icon", "type" => "asset"}
      ]}
    ])
  end

  describe ".for_pages" do
    def make_page(attrs = {})
      Page.create!({
        slug:        "p-#{SecureRandom.hex(3)}",
        title:       "A page",
        status:      "published",
        locale:      "en",
        blocks:      [],
        schema:      {"fields" => []},
        frontmatter: {},
        seo:         {}
      }.merge(attrs))
    end

    it "includes the asset's alt text in the summary" do
      asset = make_asset(alt: "A red barn")
      page = make_page(blocks: [{"type" => "gallery", "data" => {"cover" => asset.id.to_s}}])

      summary = described_class.for_pages([page])[asset.id.to_s]
      expect(summary["alt"]).to eq("A red barn")
      expect(summary).to include("id", "url", "filename", "content_type", "byte_size", "folder", "srcset", "thumb_url")
    end

    it "recurses into repeater and group fields" do
      slide = make_asset
      icon = make_asset
      page = make_page(blocks: [{"type" => "gallery", "data" => {
        "slides" => [{"image" => slide.id.to_s}],
        "cta"    => {"label" => "Go", "icon" => icon.id.to_s}
      }}])

      expect(described_class.for_pages([page]).keys).to contain_exactly(slide.id.to_s, icon.id.to_s)
    end

    it "resolves the SEO og and twitter images" do
      og = make_asset
      tw = make_asset
      page = make_page(seo: {"og_image_id" => og.id.to_s, "twitter_image_id" => tw.id.to_s})

      expect(described_class.for_pages([page]).keys).to contain_exactly(og.id.to_s, tw.id.to_s)
    end

    it "scans page frontmatter against the page's own schema" do
      hero = make_asset
      page = make_page(
        schema:      {"fields" => [{"name" => "hero", "type" => "asset"}]},
        frontmatter: {"hero" => hero.id.to_s}
      )

      expect(described_class.for_pages([page]).keys).to eq([hero.id.to_s])
    end

    it "omits ids that don't resolve and ignores blank SEO ids" do
      page = make_page(seo: {"og_image_id" => "", "twitter_image_id" => "999999"})

      expect(described_class.for_pages([page])).to eq({})
    end
  end

  describe ".for_entries" do
    let(:collection) {
      Collection.create!(slug: "posts-#{SecureRandom.hex(3)}", name: "Posts", enable_blocks: true,
                         schema: {"fields" => [
                           {"name" => "thumbnail", "type" => "asset"},
                           {"name" => "meta", "type" => "group", "of" => [{"name" => "badge", "type" => "asset"}]}
                         ]})
    }

    def make_entry(attrs = {})
      CollectionEntry.create!({
        collection:    collection,
        slug:          "e-#{SecureRandom.hex(3)}",
        title:         "T",
        status:        "published",
        locale:        "en",
        frontmatter:   {},
        body_markdown: ""
      }.merge(attrs))
    end

    it "scans frontmatter (including groups), blocks, and SEO images" do
      thumb = make_asset
      badge = make_asset
      cover = make_asset
      og = make_asset
      entry = make_entry(
        frontmatter: {"thumbnail" => thumb.id.to_s, "meta" => {"badge" => badge.id.to_s}},
        blocks:      [{"type" => "gallery", "data" => {"cover" => cover.id.to_s}}],
        seo:         {"og_image_id" => og.id.to_s}
      )

      expect(described_class.for_entries([entry]).keys)
        .to contain_exactly(thumb.id.to_s, badge.id.to_s, cover.id.to_s, og.id.to_s)
    end

    it "dedupes an asset referenced from several places across entries" do
      shared = make_asset
      a = make_entry(frontmatter: {"thumbnail" => shared.id.to_s})
      b = make_entry(seo: {"twitter_image_id" => shared.id.to_s})

      expect(described_class.for_entries([a, b]).keys).to eq([shared.id.to_s])
    end
  end
end
