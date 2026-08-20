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

ActiveRecord::Schema[8.1].define(version: 2026_08_18_110001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "document_ops", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "document_id", null: false
    t.bigint "fugue_counter", null: false
    t.string "fugue_replica", null: false
    t.string "op_type", null: false
    t.bigint "parent_counter"
    t.string "parent_replica"
    t.string "side"
    t.bigint "tenant_id", null: false
    t.text "value"
    t.index ["document_id", "created_at"], name: "index_document_ops_on_document_id_and_created_at"
    t.index ["document_id", "fugue_replica", "fugue_counter", "op_type"], name: "index_document_ops_on_document_and_fugue_id", unique: true
    t.index ["document_id"], name: "index_document_ops_on_document_id"
    t.index ["tenant_id"], name: "index_document_ops_on_tenant_id"
  end

  create_table "documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "fugue_snapshot"
    t.bigint "snapshot_through_op_id"
    t.bigint "tenant_id", null: false
    t.string "title", default: "Untitled", null: false
    t.datetime "updated_at", null: false
    t.index ["snapshot_through_op_id"], name: "index_documents_on_snapshot_through_op_id"
    t.index ["tenant_id"], name: "index_documents_on_tenant_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "role", default: "member", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "email_address"], name: "index_users_on_tenant_id_and_email_address", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
  end

  create_table "webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_name"
    t.string "external_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "processed_at"
    t.string "source", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "external_id"], name: "index_webhook_events_on_source_and_external_id", unique: true
  end

  add_foreign_key "document_ops", "documents"
  add_foreign_key "document_ops", "tenants"
  add_foreign_key "documents", "document_ops", column: "snapshot_through_op_id"
  add_foreign_key "documents", "tenants"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "tenants"
end
