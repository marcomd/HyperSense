# frozen_string_literal: true

# Creates the risk_profiles table for storing user-selected trading risk profile.
# This is a singleton table - only one record should exist at any time.
class CreateRiskProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :risk_profiles do |t|
      t.string :name, null: false, default: "moderate"
      t.string :changed_by, default: "system"

      t.timestamps
    end
  end
end
