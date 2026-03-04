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

ActiveRecord::Schema[8.0].define(version: 2026_03_04_195217) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "agents", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name", default: "", null: false
    t.string "llm_model"
    t.jsonb "model_config", default: {}
    t.bigint "parent_id"
    t.integer "origin", default: 0, null: false
    t.jsonb "metadata", default: {}
    t.string "client"
    t.index ["client"], name: "index_agents_on_client"
    t.index ["parent_id"], name: "index_agents_on_parent_id"
    t.index ["user_id"], name: "index_agents_on_user_id"
  end

  create_table "memory_chunks", force: :cascade do |t|
    t.bigint "transcript_id", null: false
    t.bigint "agent_id", null: false
    t.string "topic", null: false
    t.text "summary", null: false
    t.vector "embedding", limit: 1536
    t.text "skills_demonstrated", default: [], array: true
    t.integer "message_range_start"
    t.integer "message_range_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_memory_chunks_on_agent_id"
    t.index ["embedding"], name: "index_memory_chunks_on_embedding", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["transcript_id"], name: "index_memory_chunks_on_transcript_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "transcript_id", null: false
    t.bigint "agent_id", null: false
    t.integer "role", null: false
    t.text "content"
    t.text "thinking"
    t.integer "sequence", null: false
    t.datetime "timestamp"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_messages_on_agent_id"
    t.index ["transcript_id", "sequence"], name: "index_messages_on_transcript_id_and_sequence", unique: true
    t.index ["transcript_id"], name: "index_messages_on_transcript_id"
  end

  create_table "transcripts", force: :cascade do |t|
    t.bigint "agent_id", null: false
    t.string "source", null: false
    t.string "source_session_id"
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id"], name: "index_transcripts_on_agent_id"
    t.index ["source_session_id"], name: "index_transcripts_on_source_session_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.string "api_key", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_key"], name: "index_users_on_api_key", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "agents", "agents", column: "parent_id"
  add_foreign_key "agents", "users"
  add_foreign_key "memory_chunks", "agents"
  add_foreign_key "memory_chunks", "transcripts"
  add_foreign_key "messages", "agents"
  add_foreign_key "messages", "transcripts"
  add_foreign_key "transcripts", "agents"
end
