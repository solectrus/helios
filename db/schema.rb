# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_23_120000) do
  create_table "backups", force: :cascade do |t|
    t.bigint "bytes", null: false
    t.datetime "created_at", null: false
    t.string "destination", null: false
    t.string "external_path"
    t.string "filename", null: false
    t.text "files"
    t.string "influxdb_image"
    t.string "postgresql_image"
    t.string "s3_bucket"
    t.string "s3_endpoint_url"
    t.string "s3_prefix"
    t.index ["destination", "created_at"], name: "index_backups_on_destination_and_created_at"
    t.index ["destination", "external_path", "s3_endpoint_url", "s3_bucket", "s3_prefix", "filename"], name: "index_backups_on_destination_and_filename", unique: true
  end

  create_table "runner_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.text "last_error_message"
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_runner_logs_on_kind", unique: true
  end
end
