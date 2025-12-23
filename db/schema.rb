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

ActiveRecord::Schema[8.1].define(version: 2025_12_23_100002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "execution_logs", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.datetime "executed_at", null: false
    t.bigint "loggable_id"
    t.string "loggable_type"
    t.jsonb "request_payload", default: {}
    t.jsonb "response_payload", default: {}
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_execution_logs_on_action"
    t.index ["executed_at"], name: "index_execution_logs_on_executed_at"
    t.index ["loggable_type", "loggable_id"], name: "index_execution_logs_on_loggable"
    t.index ["loggable_type", "loggable_id"], name: "index_execution_logs_on_loggable_type_and_loggable_id"
    t.index ["status"], name: "index_execution_logs_on_status"
  end

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

  create_table "orders", force: :cascade do |t|
    t.decimal "average_fill_price", precision: 20, scale: 8
    t.datetime "created_at", null: false
    t.datetime "filled_at"
    t.decimal "filled_size", precision: 20, scale: 8
    t.string "hyperliquid_order_id"
    t.jsonb "hyperliquid_response", default: {}
    t.string "order_type", null: false
    t.bigint "position_id"
    t.decimal "price", precision: 20, scale: 8
    t.string "side", null: false
    t.decimal "size", precision: 20, scale: 8, null: false
    t.string "status", default: "pending", null: false
    t.decimal "stop_price", precision: 20, scale: 8
    t.datetime "submitted_at"
    t.string "symbol", null: false
    t.bigint "trading_decision_id"
    t.datetime "updated_at", null: false
    t.index ["hyperliquid_order_id"], name: "index_orders_on_hyperliquid_order_id", unique: true, where: "(hyperliquid_order_id IS NOT NULL)"
    t.index ["order_type"], name: "index_orders_on_order_type"
    t.index ["position_id"], name: "index_orders_on_position_id"
    t.index ["side"], name: "index_orders_on_side"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["symbol", "status"], name: "index_orders_on_symbol_and_status"
    t.index ["symbol"], name: "index_orders_on_symbol"
    t.index ["trading_decision_id"], name: "index_orders_on_trading_decision_id"
  end

  create_table "positions", force: :cascade do |t|
    t.datetime "closed_at"
    t.datetime "created_at", null: false
    t.decimal "current_price", precision: 20, scale: 8
    t.string "direction", null: false
    t.decimal "entry_price", precision: 20, scale: 8, null: false
    t.jsonb "hyperliquid_data", default: {}
    t.integer "leverage", default: 1, null: false
    t.decimal "liquidation_price", precision: 20, scale: 8
    t.decimal "margin_used", precision: 20, scale: 8
    t.datetime "opened_at", null: false
    t.decimal "size", precision: 20, scale: 8, null: false
    t.string "status", default: "open", null: false
    t.string "symbol", null: false
    t.decimal "unrealized_pnl", precision: 20, scale: 8, default: "0.0"
    t.datetime "updated_at", null: false
    t.index ["direction"], name: "index_positions_on_direction"
    t.index ["opened_at"], name: "index_positions_on_opened_at"
    t.index ["status"], name: "index_positions_on_status"
    t.index ["symbol", "status"], name: "index_positions_on_symbol_and_status"
    t.index ["symbol"], name: "index_positions_on_symbol"
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

  add_foreign_key "orders", "positions"
  add_foreign_key "orders", "trading_decisions"
  add_foreign_key "trading_decisions", "macro_strategies"
end
