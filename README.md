# Media

A plugin for the CMS (see `docs/plugins.md` in [opencms](https://github.com/Martin-Business-Consultants/opencms)),
installed by default (`config/default_plugins.yml`).

The media library at `/media`: files and images in folders, uploading them one
by one or as a zip, the picker a content form's asset fields open, and
`/api/assets`, `/api/asset_folders` and `/api/bulk_uploads`. It provides the
core's media interface (`MediaLibrary`): asset field thumbnails,
`?resolve=assets` in the API, and the Branding logo and favicon. Swap it for
another library by providing `:media` with the same interface.

Its specs run inside the CMS, with the plugin installed in `plugins/media`:

    bin/rspec plugins/media/spec
