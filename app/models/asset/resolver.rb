# frozen_string_literal: true

# Walks block/frontmatter data, gathers every `asset`-typed field value, and
# returns a flat `{id => summary}` map so an API consumer can render images
# without an N+1 round-trip per page. Used by the public-content APIs when
# the caller passes `?resolve=assets`.
#
# Inputs:
#   - `fields` is the FieldDef[] from a BlockType or Collection/Global schema
#   - `data` is the matching value hash (block.data or entry.frontmatter)
#
# Pages and entries are scanned the same way: their blocks, their frontmatter
# (against the page's own schema or the entry's collection schema), and the
# SEO image ids (`seo.og_image_id`, `seo.twitter_image_id`) the admin SEO
# panel stores. Recurses into `repeater` and `group` fields.
module Asset::Resolver
  module_function

  # The `seo` keys that hold an asset id rather than a URL.
  SEO_ASSET_KEYS = %w[og_image_id twitter_image_id].freeze

  # Resolve every asset id referenced by the given pages' blocks, frontmatter
  # and SEO images. Returns `{id => summary}` with no duplicates, after a
  # single batched DB lookup.
  def for_pages(pages)
    cache = {}
    block_types = block_types_for(pages)
    pages.each do |page|
      collect_ids_from_blocks(page.blocks, cache, block_types)
      collect_ids_from_data(page.fields, page.frontmatter || {}, cache)
      collect_ids_from_seo(page.seo, cache)
    end
    materialize(cache.keys)
  end

  # Resolve every asset id referenced by the given entries' frontmatter,
  # blocks and SEO images.
  def for_entries(entries)
    cache = {}
    block_types = block_types_for(entries)
    entries.each do |entry|
      collect_ids_from_blocks(entry.blocks, cache, block_types)
      collect_ids_from_seo(entry.seo, cache)

      collection = entry.collection
      next unless collection

      collect_ids_from_data(collection.fields, entry.frontmatter || {}, cache)
    end
    materialize(cache.keys)
  end

  def for_globals(globals)
    cache = {}
    globals.each { |g| collect_ids_from_data(g.fields, g.data || {}, cache) }
    materialize(cache.keys)
  end

  # ---- Internals ----

  # One BlockType lookup for every block across the given records, so a list
  # endpoint doesn't query per record.
  def block_types_for(records)
    slugs = records.flat_map { |r|
      blocks = r.respond_to?(:blocks) ? r.blocks : nil
      blocks.is_a?(Array) ? blocks.filter_map { |b| b["type"] if b.is_a?(Hash) } : []
    }.uniq
    return {} if slugs.empty?

    BlockType.where(slug: slugs).index_by(&:slug)
  end

  # Walk every block's data using its BlockType's fields, adding ids to
  # `cache`. Returns the collected ids array; dedupes happen at the caller.
  def collect_ids_from_blocks(blocks, cache = {}, block_types = nil)
    return cache.keys unless blocks.is_a?(Array)

    block_types ||= BlockType.where(slug: blocks.filter_map { |b| b["type"] if b.is_a?(Hash) }.uniq).index_by(&:slug)

    blocks.each do |block|
      next unless block.is_a?(Hash)

      bt = block_types[block["type"]]
      next unless bt

      collect_ids_from_data(bt.fields, block["data"] || {}, cache)
    end

    cache.keys
  end

  def collect_ids_from_seo(seo, cache)
    return unless seo.is_a?(Hash)

    SEO_ASSET_KEYS.each { |key| add_id(seo[key], cache) }
  end

  def collect_ids_from_data(fields, data, cache)
    return unless fields.is_a?(Array) && data.is_a?(Hash)

    fields.each do |field|
      name = field["name"]
      type = field["type"]

      case type
      when "asset"
        add_id(data[name], cache)
      when "repeater"
        Array(data[name]).each do |item|
          next unless item.is_a?(Hash)

          collect_ids_from_data(field["of"], item, cache)
        end
      when "group"
        collect_ids_from_data(field["of"], data[name], cache)
      end
    end
  end

  def add_id(id, cache)
    cache[id.to_s] = true if (id.is_a?(String) && !id.empty?) || id.is_a?(Integer)
  end

  # Single-query lookup. Returns a hash keyed by stringified id; missing
  # ids are omitted (the consumer can treat them as broken refs).
  def materialize(ids)
    ids = ids.reject(&:blank?).map(&:to_s).uniq
    return {} if ids.empty?

    Asset.where(id: ids).each_with_object({}) do |asset, out|
      out[asset.id.to_s] = summary_for(asset)
    end
  end

  # What a site needs to render it: absolute URLs on the CMS's host, size,
  # renditions (Asset::Delivery).
  def summary_for(asset)
    asset.delivery
  end
end
