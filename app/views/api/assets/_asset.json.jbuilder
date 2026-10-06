# frozen_string_literal: true

json.extract! record, :id, :name, :folder, :filename, :content_type, :byte_size, :url, :alt, :caption, :description, :focal_x, :focal_y, :srcset
json.created_at record.created_at&.iso8601
