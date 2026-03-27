# Unique identifier generated on each server boot.
# Used by the restart page to detect when a new instance is running.
Rails.application.config.boot_id = SecureRandom.hex(8)
