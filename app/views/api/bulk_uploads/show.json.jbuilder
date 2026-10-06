# frozen_string_literal: true

json.extract! @bulk_upload, :id, :folder, :status, :total, :processed, :succeeded, :skipped, :failed, :progress
json.finished @bulk_upload.finished?
json.errors @bulk_upload.errors_log || []
