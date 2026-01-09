# frozen_string_literal: true

# Creates the trading_modes table for storing user-selected trading mode.
# This is a singleton table - only one record should exist at any time.
#
# Modes:
# - enabled: Normal operation (can open and close positions)
# - exit_only: Only position closures allowed (set automatically by circuit breaker)
# - blocked: Complete halt (no opens or closes)
class CreateTradingModes < ActiveRecord::Migration[8.1]
  def change
    create_table :trading_modes do |t|
      t.string :mode, null: false, default: "enabled"
      t.string :changed_by, default: "system"
      t.text :reason

      t.timestamps
    end
  end
end
