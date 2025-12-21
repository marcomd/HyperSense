# frozen_string_literal: true

# Stores high-level market analysis from the macro strategist agent
#
# Generated daily (6am) by HighLevelAgent to provide context for
# low-level trading decisions throughout the day.
#
class CreateMacroStrategies < ActiveRecord::Migration[8.1]
  def change
    create_table :macro_strategies do |t|
      t.text :market_narrative, null: false
      t.string :bias, null: false  # bullish/bearish/neutral
      t.decimal :risk_tolerance, precision: 3, scale: 2, null: false  # 0.00 - 1.00
      t.jsonb :key_levels, default: {}  # { "BTC": { "support": [...], "resistance": [...] } }
      t.jsonb :context_used, default: {}  # Full context sent to LLM
      t.jsonb :llm_response, default: {}  # Raw LLM response and parsed data
      t.datetime :valid_until, null: false

      t.timestamps
    end

    add_index :macro_strategies, :valid_until
    add_index :macro_strategies, :created_at
  end
end
