# frozen_string_literal: true

require "rails_helper"

# The file manager and the folder API under it. Folders are paths on assets
# plus a remembered list of empty ones, so much of this is about that
# agreement: what the page lists, and what each folder operation does to the
# assets beneath it.
RSpec.describe "File manager", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  before do
    sign_in_as user
    Asset.with_discarded.destroy_all
    Setting.delete_key("assets")
  end

  def upload(name, folder: "/", **attrs)
    Asset.create!(folder: folder, file: {io: StringIO.new("PNG"), filename: name, content_type: "image/png"}, **attrs)
  end

  def png(name = "logo.png")
    Rack::Test::UploadedFile.new(StringIO.new("\x89PNG\r\n\x1a\nfake"), "image/png", original_filename: name)
  end

  describe "the page" do
    it "shows every file, narrowed to a folder by its filter, with that folder's subfolders" do
      upload("a.png")
      upload("b.png", folder: "/brand/logos")
      AssetFolders.create("/campaigns")

      get file_manager_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Media Library", "a.png", "b.png", "All folders", "/brand/logos", "/campaigns", "2 media items")

      get file_manager_path(folder: "/")
      expect(response.body).to include("a.png", "campaigns")
      expect(response.body).not_to include("b.png")

      get file_manager_path(folder: "/brand/logos", view: "table")
      expect(response.body).to include("b.png", "Rename folder")
      expect(response.body).not_to include("a.png")
    end

    it "filters by kind of file and by the month it was added" do
      upload("photo.png")
      Asset.create!(file: {io: StringIO.new("%PDF"), filename: "menu.pdf", content_type: "application/pdf"})
      travel_to(Time.utc(2025, 3, 10)) { upload("old.png") }

      get file_manager_path(kind: "documents")
      expect(response.body).to include("menu.pdf")
      expect(response.body).not_to include("photo.png")

      get file_manager_path(kind: "images", month: "2025-03")
      expect(response.body).to include("old.png", "March 2025")
      expect(response.body).not_to include("photo.png", "menu.pdf")
    end

    it "opens a file's details in the library's sheet, and saves them there" do
      asset = upload("hero.png")

      get file_manager_path
      expect(response.body).to include('turbo-frame id="asset_details"', 'data-turbo-frame="asset_details"')

      get file_manager_asset_path(asset), headers: {"Turbo-Frame" => "asset_details"}
      expect(response.body).to include("Alternative text", "Caption", "Description", "hero.png")
      expect(response.body).not_to include("<header")

      patch file_manager_asset_path(asset), params: {asset: {alt: "The team", caption: "Spring 2026", description: "Taken at the mill"}}
      expect(asset.reload).to have_attributes(alt: "The team", caption: "Spring 2026", description: "Taken at the mill")
    end

    it "searches every folder by file or display name" do
      upload("menu.png", folder: "/deep/down")
      upload("other.png", name: "Winter menu")
      upload("nope.png")

      get file_manager_path(q: "menu")

      expect(response.body).to include("menu.png", "Winter menu")
      expect(response.body).not_to include("nope.png")
    end

    it "leaves trashed assets out" do
      upload("gone.png").discard!

      get file_manager_path

      expect(response.body).not_to include("gone.png")
    end

    it "shows a file's details, and the records that use it" do
      asset = upload("hero.png", alt: "The mill at dusk")
      # A real reference, stored the way Page::Referencing stores one.
      Page.create!(slug: "about", title: "About us", status: "draft", locale: "en",
        schema: {"fields" => [{"name" => "cover_id", "type" => "asset"}]}, frontmatter: {"cover_id" => asset.id.to_s})

      get file_manager_asset_path(asset)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("hero.png", "The mill at dusk", "About us", "Copy URL")
    end
  end

  describe "uploading" do
    it "adds the files to the folder" do
      expect {
        post file_manager_assets_path, params: {folder: "/brand", files: [png("a.png"), png("b.png")]}
      }.to change(Asset, :count).by(2)

      expect(response).to redirect_to(file_manager_path(folder: "/brand"))
      expect(flash[:notice]).to eq("Uploaded 2 files.")
      expect(Asset.pluck(:folder).uniq).to eq(["/brand"])
      expect(AuditLog.last.action).to eq("assets.uploaded")
    end

    it "takes the signed ids a direct upload leaves" do
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("GIF89a"), filename: "direct.gif", content_type: "image/gif")

      post file_manager_assets_path, params: {folder: "/", files: [blob.signed_id]}

      expect(Asset.last.filename).to eq("direct.gif")
    end

    it "asks for files" do
      post file_manager_assets_path, params: {folder: "/"}

      expect(flash[:alert]).to match(/Choose one or more files/)
    end

    it "unpacks a zip in the background and follows it" do
      post file_manager_bulk_uploads_path, params: {folder: "/zips", archive: Rack::Test::UploadedFile.new(StringIO.new("PK"), "application/zip", original_filename: "x.zip")}

      bulk_upload = BulkUpload.last
      expect(response).to redirect_to(file_manager_bulk_upload_path(bulk_upload))
      expect(BulkUpload::UnpackJob).to have_been_enqueued.with(bulk_upload.id)

      get file_manager_bulk_upload_path(bulk_upload)
      expect(response.body).to include("/zips", "data-controller=\"refresh\"")

      bulk_upload.update!(status: "succeeded", total: 3, processed: 3, succeeded: 3)
      get file_manager_bulk_upload_path(bulk_upload)
      expect(response.body).to include("See the folder")
      expect(response.body).not_to include("data-controller=\"refresh\"")
    end
  end

  describe "changing files" do
    it "saves a file's name, alt text and folder" do
      asset = upload("a.png")

      patch file_manager_asset_path(asset), params: {asset: {name: "Logo", alt: "Our logo", folder: "brand"}}

      expect(response).to redirect_to(file_manager_asset_path(asset))
      expect(asset.reload).to have_attributes(name: "Logo", alt: "Our logo", folder: "/brand")
    end

    it "shows the page again for a folder that can't be" do
      asset = upload("a.png")

      patch file_manager_asset_path(asset), params: {asset: {folder: "/bad?name"}}

      expect(response).to have_http_status(:unprocessable_content)
      expect(asset.reload.folder).to eq("/")
    end

    it "sends one file to the trash" do
      asset = upload("a.png", folder: "/x")

      delete file_manager_asset_path(asset)

      expect(response).to redirect_to(file_manager_path(folder: "/x"))
      expect(Asset.with_discarded.find(asset.id)).to be_discarded
    end

    it "moves and trashes the ticked files" do
      a = upload("a.png")
      b = upload("b.png")
      c = upload("c.png")

      post file_manager_moves_path, params: {ids: [a.id, b.id], to: "/archive"}
      expect(flash[:notice]).to eq("Moved 2 files to /archive.")
      expect([a.reload.folder, b.reload.folder, c.reload.folder]).to eq(["/archive", "/archive", "/"])

      post file_manager_bulk_deletions_path, params: {ids: [a.id, c.id]}
      expect(Asset.pluck(:id)).to eq([b.id])
    end
  end

  describe "folders" do
    it "makes, renames and deletes one through the page" do
      post file_manager_folder_path, params: {parent: "/brand", name: "logos"}
      expect(response).to redirect_to(file_manager_path(folder: "/brand/logos"))
      expect(AssetFolders.remembered).to include("/brand/logos")

      asset = upload("a.png", folder: "/brand/logos")
      patch file_manager_folder_path, params: {path: "/brand/logos", name: "marks"}
      expect(asset.reload.folder).to eq("/brand/marks")

      delete file_manager_folder_path(path: "/brand/marks")
      expect(response).to redirect_to(file_manager_path(folder: "/brand"))
      expect(Asset.with_discarded.find(asset.id)).to be_discarded
    end

    it "says why a name won't do" do
      post file_manager_folder_path, params: {parent: "/", name: "bad?name"}

      expect(flash[:alert]).to match(/letters, numbers/)
    end
  end

  describe "the folder API" do
    it "remembers an empty folder so it shows up on the page" do
      post "/api/asset_folders", params: {path: "brand/ logos "}, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["path"]).to eq("/brand/logos")
      get file_manager_path
      expect(response.body).to include("/brand/logos")
    end

    it "refuses a name the asset column wouldn't accept" do
      post "/api/asset_folders", params: {path: "/bad?name"}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to match(/letters, numbers/)
    end

    it "moves the folder, its subfolders and everything in them" do
      a = upload("a.png", folder: "/old")
      b = upload("b.png", folder: "/old/deep")
      other = upload("c.png", folder: "/older")
      AssetFolders.create("/old/empty")

      patch "/api/asset_folders", params: {path: "/old", to: "/new"}, as: :json

      expect(response.parsed_body).to eq("path" => "/new", "moved" => 2)
      expect([a.reload.folder, b.reload.folder, other.reload.folder]).to eq(["/new", "/new/deep", "/older"])
      expect(AssetFolders.remembered).to include("/new/empty")
      expect(AssetFolders.remembered).not_to include("/old/empty")
    end

    it "won't move a folder into itself" do
      upload("a.png", folder: "/old")

      patch "/api/asset_folders", params: {path: "/old", to: "/old/inner"}, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "trashes the assets beneath it and forgets the folder" do
      a = upload("a.png", folder: "/gone")
      kept = upload("c.png", folder: "/goner")

      delete "/api/asset_folders", params: {path: "/gone"}, as: :json

      expect(response.parsed_body["discarded"]).to eq(1)
      expect(Asset.with_discarded.find(a.id)).to be_discarded
      expect(kept.reload).to be_kept
    end
  end

  context "as a reader" do
    let(:reader_role) { Role.create!(name: "Reader #{SecureRandom.hex(2)}", permissions: %w[assets:read]) }
    let(:user) { create(:user, admin: false, role: reader_role) }

    it "sees the files without the ways to change them, and can't" do
      asset = upload("a.png", folder: "/x")

      get file_manager_path(folder: "/x")
      expect(response.body).to include("a.png")
      expect(response.body).not_to include("Upload files", "New folder", "assets_bulk")

      post file_manager_folder_path, params: {parent: "/", name: "y"}
      expect(AssetFolders.remembered).to be_empty
      delete file_manager_asset_path(asset)
      expect(asset.reload).to be_kept
      post "/api/asset_folders", params: {path: "/x"}, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
