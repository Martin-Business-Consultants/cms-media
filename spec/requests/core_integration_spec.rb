# frozen_string_literal: true

require "rails_helper"
require "rubygems/package"
require "zlib"
require "zip"

# What Media does for the core, through MediaLibrary and the core's API: the
# picker asset fields open, the Branding logo, backups holding the files,
# bulk uploads and folder renames over the API, and a preview draft's assets.
RSpec.describe "Media in the core", type: :request do
  let(:admin) { create(:user) }
  let(:api) { {"Authorization" => "Bearer #{admin.api_token.token}"} }

  def api_for(user) = {"Authorization" => "Bearer #{user.api_token.token}"}

  def json = JSON.parse(response.body)

  # [action, metadata without via] of the rows a block writes.
  def rows_from
    from = AuditLog.maximum(:id).to_i
    yield
    AuditLog.where("id > ?", from).order(:id).map { [it.action, it.metadata.except("via")] }
  end

  def admin_rows(&)
    sign_in_as admin
    rows_from(&)
  end

  # SiteBackup#dump_to closes its IO, so read the bytes back through a fresh reader.
  def entries_of(backup)
    io = StringIO.new
    backup.dump_to(io)
    entries = {}
    Zlib::GzipReader.wrap(StringIO.new(io.string)) do |gz|
      Gem::Package::TarReader.new(gz) { |tar| tar.each { |entry| entries[entry.full_name] = entry.read } }
    end
    entries
  end

  describe "the asset picker" do
    before { sign_in_as admin }

    it "lists a folder, searches every folder, and uploads into the folder" do
      Asset.create!(folder: "/", file: fixture_file_upload(Rails.root.join("public/icon.png"), "image/png"), name: "Logo")

      get asset_picker_path
      expect(response.body).to include("turbo-frame", "Logo", "media--asset-picker#pick")

      get asset_picker_path(q: "logo")
      expect(response.body).to include("Logo")

      expect {
        post asset_picker_path, params: {folder: "/", files: [fixture_file_upload(Rails.root.join("public/icon.svg"), "image/svg+xml")]}
      }.to change(Asset, :count).by(1)
      expect(response.body).to include("icon")
    end
  end

  describe "branding" do
    it "takes a logo dropped on its zone into the media library, and Remove clears it" do
      sign_in_as admin
      png = Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n\x1a\nfake"), "image/png", original_filename: "logo.png")

      get settings_branding_path
      expect(response.body).to include("Drop an image here, or click to choose")
      expect(response.body).not_to include("No logo")

      patch settings_branding_path, params: {branding: {logo_id: "", logo_file: png}}
      logo = Asset.order(:id).last
      expect(logo).to have_attributes(folder: "/branding")
      expect(Setting.get("branding")["logo_id"]).to eq(logo.id)

      patch settings_branding_path, params: {branding: {logo_id: ""}}
      expect(Setting.get("branding")).not_to have_key("logo_id")
    end

    it "refuses a file that isn't an image" do
      sign_in_as admin
      text = Rack::Test::UploadedFile.new(StringIO.new("hi"), "text/plain", original_filename: "logo.txt")

      expect { patch settings_branding_path, params: {branding: {logo_file: text}} }.not_to change(Asset, :count)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("The logo has to be an image.")
    end
  end

  it "includes every uploaded file an asset holds" do
    asset = Asset.new(folder: "/")
    asset.file.attach(io: StringIO.new("PNG-BYTES"), filename: "logo.png", content_type: "image/png")
    asset.save!

    entries = entries_of(SiteBackup.new)

    expect(entries["blobs/#{asset.file.blob.key}"]).to eq("PNG-BYTES")
  end

  describe "POST /api/bulk_uploads" do
    let(:zip) do
      Tempfile.new(["up", ".zip"]).tap do |file|
        Zip::OutputStream.open(file.path) { it.put_next_entry("a.txt"); it.write("hi") }
      end
    end

    def archive = Rack::Test::UploadedFile.new(zip.path, "application/zip")

    it "needs assets:write" do
      reader = create(:user, admin: false, role: create(:role, permissions: %w[assets:read]))

      post "/api/bulk_uploads", params: {archive: archive}, headers: api_for(reader)

      expect(response).to have_http_status(:forbidden)
      expect(json).to include("capability" => "assets:write")
      expect(BulkUpload.count).to eq(0)
    end

    it "is recorded as the file manager's upload is" do
      post "/api/bulk_uploads", params: {archive: archive}, headers: api_for(admin)

      expect(response).to have_http_status(:created)
      expect(AuditLog.last).to have_attributes(action: "assets.bulk_upload_queued")
      expect(AuditLog.last.metadata).to include("folder" => "/", "via" => "api")
    end
  end

  it "includes a page's assets in the delivery API, with absolute URLs" do
    BlockType.seed
    asset = Asset.create!(name: "pic.png", folder: "/", file: {io: StringIO.new("x"), filename: "pic.png", content_type: "image/png"})
    Page.create!(slug: "home", title: "Home", status: "published", blocks: [{"id" => "b1", "type" => "image", "data" => {"asset_id" => asset.id.to_s, "alt" => "a"}}])

    get "/api/v1/pages/home", headers: api_for(admin)

    expect(json.dig("included", "assets").keys).to eq([asset.id.to_s])
    expect(json.dig("included", "assets", asset.id.to_s)).to include("filename" => "pic.png")
    expect(json.dig("included", "assets", asset.id.to_s, "url")).to start_with("http://example.com/")
  end

  it "records a folder rename by its normalized paths from both" do
    Asset.create!(name: "x.png", folder: "/brand/logos", file: {io: StringIO.new("x"), filename: "x.png", content_type: "image/png"})

    from_api = rows_from { patch "/api/asset_folders", params: {path: "brand/logos", to: "brand/marks/"}, headers: api, as: :json }
    from_admin = admin_rows { patch file_manager_folder_path, params: {path: "/brand/marks", to: "/brand/logos"} }

    expect(from_api.first).to eq(["asset_folder.renamed", {"from" => "/brand/logos", "to" => "/brand/marks", "moved" => 1}])
    expect(from_admin.first).to eq(["asset_folder.renamed", {"from" => "/brand/marks", "to" => "/brand/logos", "moved" => 1}])
  end
end
