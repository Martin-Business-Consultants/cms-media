# frozen_string_literal: true

json.assets @assets, partial: "api/assets/asset", as: :record
json.pagination do
  json.page @page
  json.per @per
  json.total @total
  json.total_pages @total_pages
end
