# frozen_string_literal: true

# An asset as a site renders it (Asset::Delivery: absolute URLs on the CMS's
# host, width and height, renditions), with what the library edits besides.
json.merge! record.delivery
json.extract! record, :name, :caption, :description
json.created_at record.created_at&.iso8601
