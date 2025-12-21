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

ActiveRecord::Schema[8.1].define(version: 2025_12_21_150001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "macro_strategies", force: :cascade do |t|
    t.string "bias", null: false
    t.jsonb "context_used", default: {}
    t.datetime "created_at", null: false
    t.jsonb "key_levels", default: {}
    t.jsonb "llm_response", default: {}
    t.text "market_narrative", null: false
    t.decimal "risk_tolerance", precision: 3, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.datetime "valid_until", null: false
    t.index ["created_at"], name: "index_macro_strategies_on_created_at"
    t.index ["valid_until"], name: "index_macro_strategies_on_valid_until"
  end

  create_table "market_snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.decimal "high_24h", precision: 20, scale: 8
    t.jsonb "indicators", default: {}
    t.decimal "low_24h", precision: 20, scale: 8
    t.decimal "price", precision: 20, scale: 8, null: false
    t.decimal "price_change_pct_24h", precision: 10, scale: 4
    t.jsonb "sentiment", default: {}
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.decimal "volume_24h", precision: 20, scale: 8
    t.index ["captured_at"], name: "index_market_snapshots_on_captured_at"
    t.index ["symbol", "captured_at"], name: "index_market_snapshots_on_symbol_and_captured_at", unique: true
    t.index ["symbol"], name: "index_market_snapshots_on_symbol"
  end

  create_table "trading_decisions", force: :cascade do |t|
    t.decimal "confidence", precision: 3, scale: 2
    t.jsonb "context_sent", default: {}
    t.datetime "created_at", null: false
    t.string "direction"
    t.boolean "executed", default: false
    t.jsonb "llm_response", default: {}
    t.bigint "macro_strategy_id"
    t.string "operation"
    t.jsonb "parsed_decision", default: {}
    t.string "rejection_reason"
    t.string "status", default: "pending"
    t.string "symbol", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_trading_decisions_on_created_at"
    t.index ["macro_strategy_id"], name: "index_trading_decisions_on_macro_strategy_id"
    t.index ["status"], name: "index_trading_decisions_on_status"
    t.index ["symbol", "created_at"], name: "index_trading_decisions_on_symbol_and_created_at"
    t.index ["symbol"], name: "index_trading_decisions_on_symbol"
  end

  add_foreign_key "trading_decisions", "macro_strategies"
end
