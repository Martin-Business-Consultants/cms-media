# frozen_string_literal: true

# The folder tree of the asset library, which has no table of its own.
#
# A folder is a path on `assets.folder`. Most exist because an asset is in
# them; the ones a person created and hasn't filled yet are kept in
# Setting["assets"]["folders"] so they survive a reload. This module is the
# one place that knows both sources and the path rules, so the controller
# and the API agree on what a folder is. Creating, renaming and deleting a
# folder each record an event; rename and delete record the paths as the
# caller gave them (the API has always audited what was asked for).
module AssetFolders
  SETTING_KEY = "assets"

  class InvalidPath < StandardError; end

  # Every folder path there is, ancestors included, sorted, without root.
  # `/a/b/c` implies `/a` and `/a/b` even when nothing sits directly in them.
  def self.all(asset_folders)
    (asset_folders + remembered).flat_map { |f| ancestors(f) }.uniq.sort
  end

  # Normalizes a user-typed path to the form `Asset::FOLDER_FORMAT` accepts,
  # or raises with a message fit for a form.
  def self.normalize(path)
    parts = path.to_s.split("/").map(&:strip).reject(&:empty?)
    return "/" if parts.empty?

    normalized = "/#{parts.join("/")}"
    raise InvalidPath, "Folder names may use letters, numbers, spaces, dashes and underscores." unless normalized.match?(Asset::FOLDER_FORMAT)

    normalized
  end

  def self.create(path)
    path = normalize(path)
    raise InvalidPath, "That's the root folder." if path == "/"

    remember(remembered + [path])
    Event.record("asset_folder.created", path: path)
    path
  end

  # Moves everything under `from` to `to` — the folder itself and all of its
  # descendants — and forgets any remembered empty folders along the way.
  # Returns the number of assets moved.
  def self.rename(from, to)
    from = normalize(from)
    to = normalize(to)
    raise InvalidPath, "The root folder can't be renamed." if from == "/"
    raise InvalidPath, "A folder can't be moved into itself." if to == from || to.start_with?("#{from}/")

    moved = 0
    Asset.transaction do
      scope(from).find_each do |asset|
        asset.update!(folder: asset.folder.sub(from, to))
        moved += 1
      end
      remember(remembered.map { |f| f == from || f.start_with?("#{from}/") ? f.sub(from, to) : f } + [to])
    end
    Event.record("asset_folder.renamed", from: from, to: to, moved: moved)
    moved
  end

  # Discards every asset under the folder (they go to the trash like any
  # other delete) and forgets the folder. Returns the number discarded.
  def self.delete(path)
    path = normalize(path)
    raise InvalidPath, "The root folder can't be deleted." if path == "/"

    discarded = 0
    Asset.transaction do
      scope(path).find_each do |asset|
        asset.discard!
        discarded += 1
      end
      remember(remembered.reject { |f| f == path || f.start_with?("#{path}/") })
    end
    Event.record("asset_folder.deleted", path: path, discarded: discarded)
    discarded
  end

  # The folders directly inside `parent` ("/" for the top level), from a
  # list AssetFolders.all returned.
  def self.children(folders, parent)
    parent = normalize(parent)
    depth = parent == "/" ? 1 : parent.count("/") + 1
    prefix = parent == "/" ? "/" : "#{parent}/"
    folders.select { |folder| folder.start_with?(prefix) && folder.count("/") == depth }
  end

  # "/brand/logos" → "logos"; "/" → "All files".
  def self.name(path) = path == "/" ? "All files" : path.split("/").last

  # "/brand/logos" → "/brand"; "/brand" → "/".
  def self.parent(path)
    parts = path.to_s.split("/").reject(&:empty?)
    parts.size <= 1 ? "/" : "/#{parts[0..-2].join("/")}"
  end

  def self.scope(path)
    Asset.where(folder: path).or(Asset.where("folder LIKE ?", "#{ActiveRecord::Base.sanitize_sql_like(path)}/%"))
  end

  def self.remembered
    Array(Setting.get(SETTING_KEY)["folders"]).map(&:to_s)
  end

  def self.remember(folders)
    Setting.set(SETTING_KEY, folders: folders.uniq.sort)
  end

  def self.ancestors(folder)
    parts = folder.to_s.split("/").reject(&:empty?)
    parts.each_index.map { |i| "/#{parts[0..i].join("/")}" }
  end
end
