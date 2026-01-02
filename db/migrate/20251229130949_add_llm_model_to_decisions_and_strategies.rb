# frozen_string_literal: true

# Adds llm_model column to trading_decisions and macro_strategies tables
# to track which LLM model made each decision for debugging and performance analysis.
class AddLLMModelToDecisionsAndStrategies < ActiveRecord::Migration[8.1]
  def change
    add_column :trading_decisions, :llm_model, :string
    add_column :macro_strategies, :llm_model, :string
  end
end
