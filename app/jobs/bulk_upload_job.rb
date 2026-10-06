# frozen_string_literal: true

# Jobs queued before BulkUpload::UnpackJob took over carry this name. Kept one
# release so they still run; remove it once those have drained.
class BulkUploadJob < BulkUpload::UnpackJob
end
