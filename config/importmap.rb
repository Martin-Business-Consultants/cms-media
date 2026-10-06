# frozen_string_literal: true

# The Media plugin's Stimulus controllers, loaded with the admin's own
# (controllers/index.js loads every pin under "controllers"):
# media--file-drop, media--direct-upload, media--asset-picker.
pin_all_from Media::Engine.root.join("app/javascript/controllers/media"), under: "controllers/media", to: "controllers/media"
