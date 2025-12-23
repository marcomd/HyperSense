# frozen_string_literal: true

class AddRiskFieldsToPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :positions, :stop_loss_price, :decimal, precision: 20, scale: 8
    add_column :positions, :take_profit_price, :decimal, precision: 20, scale: 8
    add_column :positions, :risk_amount, :decimal, precision: 20, scale: 8
    add_column :positions, :realized_pnl, :decimal, precision: 20, scale: 8, default: 0
    add_column :positions, :close_reason, :string
  end
end
