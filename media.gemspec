# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "media"
  spec.version = "1.0.0"
  spec.summary = "The CMS's media library: files and folders, uploads, the picker asset fields open"
  spec.authors = ["Martin Business Consultants"]
  spec.files = Dir["{app,config,db,lib}/**/*"]
  spec.required_ruby_version = ">= 3.3"
  spec.add_dependency "rails", ">= 8.1"
end
