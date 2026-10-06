# frozen_string_literal: true

# Adding files to the library: several at once into a folder (the file
# manager and the asset picker, where a bad file fails alone), or one through
# the API, which raises on anything invalid. Each upload is one event, however
# many files it saved.
module Asset::Uploadable
  extend ActiveSupport::Concern

  class_methods do
    # files: uploads, or signed ids from Active Storage direct uploads.
    # Returns every asset, saved or not; the unsaved carry their errors.
    def upload(files, folder:)
      assets = files.map { |file| create(folder: folder, file: file) }
      saved = assets.count(&:persisted?)
      Event.record("assets.uploaded", folder: folder, count: saved) if saved.positive?
      assets
    end

    # Attributes left nil fall back to the column defaults (the focal point
    # defaults to the centre), so they're dropped rather than written as nil.
    def upload!(file, **attributes)
      asset = new(attributes.compact)
      asset.file.attach(file)
      asset.save!
      Event.record("assets.uploaded", folder: asset.folder, count: 1)
      asset
    end
  end
end
