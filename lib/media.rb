# frozen_string_literal: true

require "media/engine"

# Media: the library of files and images (Asset, in folders), uploading them
# one by one or as a zip, the picker a content form's asset fields open, and
# the API under /api/assets. It's what the core's media interface (Media in
# the core, Cms::Plugins.provided(:media)) reads: an asset field's thumbnail,
# ?resolve=assets, the Branding logo. Installed by default from its own
# repository (config/default_plugins.yml in the core), and on by default.
#
# Its models keep the names and tables they had in the core (assets,
# bulk_uploads) — they predate plugins; a new table would be prefixed.
module Media
end
