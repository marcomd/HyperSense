# frozen_string_literal: true

# Adds peak tracking and trailing stop columns to positions table.
#
# Peak tracking enables monitoring the highest price reached since entry,
# which allows the agent to detect when profit is fading from peak.
#
# Trailing stop columns enable automatic profit protection by moving
# stop-loss up as price rises.
class AddPeakAndTrailingStopToPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :positions, :peak_price, :decimal, precision: 20, scale: 8
    add_column :positions, :peak_price_at, :datetime
    add_column :positions, :trailing_stop_active, :boolean, default: false
    add_column :positions, :original_stop_loss_price, :decimal, precision: 20, scale: 8
  end
end
