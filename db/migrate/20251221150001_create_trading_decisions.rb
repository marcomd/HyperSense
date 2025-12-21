# frozen_string_literal: true

# Records each trading decision made by the low-level agent
#
# Tracks the full context sent to the LLM, raw response, parsed decision,
# and execution status for audit trail and learning.
#
class CreateTradingDecisions < ActiveRecord::Migration[8.1]
  def change
    create_table :trading_decisions do |t|
      t.references :macro_strategy, foreign_key: true, null: true
      t.string :symbol, null: false
      t.jsonb :context_sent, default: {}  # Full prompt context
      t.jsonb :llm_response, default: {}  # Raw LLM output
      t.jsonb :parsed_decision, default: {}  # Structured decision after validation
      t.string :operation  # open/close/hold
      t.string :direction  # long/short
      t.decimal :confidence, precision: 3, scale: 2  # 0.00 - 1.00
      t.boolean :executed, default: false
      t.string :rejection_reason
      t.string :status, default: "pending"  # pending/approved/rejected/executed/failed

      t.timestamps
    end

    add_index :trading_decisions, :symbol
    add_index :trading_decisions, :status
    add_index :trading_decisions, :created_at
    add_index :trading_decisions, [ :symbol, :created_at ]
  end
end
