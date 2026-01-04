# frozen_string_literal: true

# Adds risk_profile_name to trading_decisions for audit trail.
# Stores which profile was active when each decision was made.
class AddRiskProfileNameToTradingDecisions < ActiveRecord::Migration[8.1]
  def change
    add_column :trading_decisions, :risk_profile_name, :string, default: "moderate"
  end
end
