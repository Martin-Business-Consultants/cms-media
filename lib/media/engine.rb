# frozen_string_literal: true

module Media
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it — the core's asset fields,
  # ?resolve=assets and the Branding logo read it through MediaLibrary.
  class Engine < ::Rails::Engine
    initializer "media.routes" do |app|
      app.routes.append do
        admin = proc do
          # The library, at /cms/media (/media on a core from before /cms). Folders are paths on assets (AssetFolders);
          # the folder resource is addressed by ?path=. The route helpers keep
          # the file_manager name; /file_manager links from before land here.
          get "media", to: "file_manager#index", as: :file_manager
          get "file_manager(/*rest)", to: redirect { |params, request| "#{"/#{Cms::PATH}" if defined?(Cms::PATH)}/media#{"/" + params[:rest] if params[:rest]}#{"?" + request.query_string if request.query_string.present?}" }
          namespace :file_manager, path: "media" do
            resources :assets, only: [:show, :create, :update, :destroy]
            resource :folder, only: [:create, :update, :destroy]
            resources :moves, only: :create
            resources :bulk_deletions, only: :create
            resources :bulk_uploads, only: [:create, :show]
          end

          # The picker a content form's asset fields open.
          resource :asset_picker, only: [:show, :create]
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call

        namespace :api, defaults: {format: :json} do
          resources :assets, only: [:index, :create, :show, :update, :destroy]
          # Folders are paths on assets, not records: one resource, addressed by path.
          resource :asset_folders, only: [:create, :update, :destroy]
          resources :bulk_uploads, only: [:create, :show]
        end
      end
    end

    # The plugin's Stimulus controllers, pinned beside the admin's
    # (config/importmap.rb).
    initializer "media.importmap", before: "importmap" do |app|
      app.config.importmap.paths << root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << root.join("app/javascript")
    end

    initializer "media.assets" do |app|
      app.config.assets.paths << root.join("app/javascript")
    end

    config.to_prepare do
      Cms::Plugins.register :media, name: "Media", version: "1.0.0", author: "Martin Business Consultants",
        enabled_by_default: true, requires: ">= 1.0",
        description: "The media library: files and images in folders, uploading them one by one or as a zip, " \
                     "the picker asset fields open, and /api/assets.",
        adopt_if: -> { Asset.with_discarded.exists? }

      Cms::Plugins.provide :media, :media, -> { Media::Provider }

      Cms::Plugins.menu :media, :media, label: "Media", icon: "image", group: "Content", after: [:forms, :globals],
        path: -> { file_manager_path }, capability: "assets:read"
      Cms::Plugins.submenu :media, :media, label: "Library", path: -> { file_manager_path }, capability: "assets:read"
      Cms::Plugins.new_item :media, label: "Media", path: -> { file_manager_path(upload: 1) }, capability: "assets:write",
        after: "Global"
      Cms::Plugins.slot :content_form, :media, "media/slots/picker"
      Cms::Plugins.stylesheet :media, "media/file-manager"

      Cms::Plugins.counts :media, after: :globals, assets: -> { Asset.count }
      Cms::Plugins.trashable :media, "asset", "Asset", label: "Assets", after: "global",
        meta: ->(asset) { {filename: asset.filename, size: ActiveSupport::NumberHelper.number_to_human_size(asset.byte_size)} }

      Cms::Plugins.api :media, "/api/assets", description: "The media library: list, upload, change and delete files."
      Cms::Plugins.api :media, "/api/asset_folders", description: "Folders: create, rename and delete them by path."
      Cms::Plugins.api :media, "/api/bulk_uploads", description: "A zip of images, unpacked into a folder."
    end
  end
end
