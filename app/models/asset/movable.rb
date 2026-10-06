# frozen_string_literal: true

# Moving assets into another folder, all or none, as one event.
module Asset::Movable
  extend ActiveSupport::Concern

  class_methods do
    def move_all(assets, to:)
      transaction { assets.each { it.update!(folder: to) } }
      Event.record("assets.moved", to: to, count: assets.size)
      assets
    end
  end
end
