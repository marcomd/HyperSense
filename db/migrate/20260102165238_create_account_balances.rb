# frozen_string_literal: true

# Creates the account_balances table for tracking balance history.
# This enables accurate PnL calculation by detecting deposits/withdrawals
# and distinguishing them from trading gains/losses.
class CreateAccountBalances < ActiveRecord::Migration[8.1]
  def change
    create_table :account_balances do |t|
      # Core balance fields
      t.decimal :balance, precision: 20, scale: 8, null: false
      t.decimal :previous_balance, precision: 20, scale: 8
      t.decimal :delta, precision: 20, scale: 8

      # Event classification
      t.string :event_type, null: false # initial, sync, deposit, withdrawal, adjustment

      # Source and notes
      t.string :source, default: "hyperliquid"
      t.text :notes

      # Raw Hyperliquid API response for debugging and reconciliation
      t.jsonb :hyperliquid_data, default: {}

      # When this balance was recorded
      t.datetime :recorded_at, null: false

      t.timestamps
    end

    add_index :account_balances, :event_type
    add_index :account_balances, :recorded_at
    add_index :account_balances, [ :event_type, :recorded_at ]
  end
end
