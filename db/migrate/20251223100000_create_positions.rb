# frozen_string_literal: true

class CreatePositions < ActiveRecord::Migration[8.1]
  def change
    create_table :positions do |t|
      t.string :symbol, null: false
      t.string :direction, null: false
      t.decimal :size, precision: 20, scale: 8, null: false
      t.decimal :entry_price, precision: 20, scale: 8, null: false
      t.decimal :current_price, precision: 20, scale: 8
      t.integer :leverage, default: 1, null: false
      t.decimal :margin_used, precision: 20, scale: 8
      t.decimal :unrealized_pnl, precision: 20, scale: 8, default: 0
      t.decimal :liquidation_price, precision: 20, scale: 8
      t.string :status, default: "open", null: false
      t.jsonb :hyperliquid_data, default: {}
      t.datetime :opened_at, null: false
      t.datetime :closed_at

      t.timestamps
    end

    add_index :positions, :symbol
    add_index :positions, :status
    add_index :positions, :direction
    add_index :positions, [ :symbol, :status ]
    add_index :positions, :opened_at
  end
end
