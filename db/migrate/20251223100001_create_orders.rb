# frozen_string_literal: true

class CreateOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :orders do |t|
      t.references :trading_decision, null: true, foreign_key: true
      t.references :position, null: true, foreign_key: true
      t.string :symbol, null: false
      t.string :order_type, null: false
      t.string :side, null: false
      t.decimal :size, precision: 20, scale: 8, null: false
      t.decimal :price, precision: 20, scale: 8
      t.decimal :stop_price, precision: 20, scale: 8
      t.string :status, default: "pending", null: false
      t.string :hyperliquid_order_id
      t.jsonb :hyperliquid_response, default: {}
      t.decimal :filled_size, precision: 20, scale: 8
      t.decimal :average_fill_price, precision: 20, scale: 8
      t.datetime :submitted_at
      t.datetime :filled_at

      t.timestamps
    end

    add_index :orders, :symbol
    add_index :orders, :status
    add_index :orders, :side
    add_index :orders, :order_type
    add_index :orders, :hyperliquid_order_id, unique: true, where: "hyperliquid_order_id IS NOT NULL"
    add_index :orders, [ :symbol, :status ]
  end
end
