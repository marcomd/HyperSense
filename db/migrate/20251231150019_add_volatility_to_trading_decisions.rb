# frozen_string_literal: true

# Adds volatility tracking columns to trading decisions
# for dynamic job scheduling based on market conditions
#
# volatility_level: enum (very_high: 0, high: 1, medium: 2, low: 3)
# atr_value: the ATR value used to determine volatility
# next_cycle_interval: the interval in minutes for the next trading cycle
class AddVolatilityToTradingDecisions < ActiveRecord::Migration[8.1]
  def change
    # Volatility level as integer enum (default: medium = 2)
    add_column :trading_decisions, :volatility_level, :integer, default: 2

    # ATR value with precision for financial data
    add_column :trading_decisions, :atr_value, :decimal, precision: 20, scale: 8

    # Next cycle interval in minutes (default: 12 = medium)
    add_column :trading_decisions, :next_cycle_interval, :integer, default: 12

    # Index for querying by volatility level
    add_index :trading_decisions, :volatility_level
  end
end
