# frozen_string_literal: true

# Main trading cycle job - orchestrates the entire trading workflow
#
# Runs every 5 minutes (configured in config/recurring.yml) to:
# 1. Ensure valid macro strategy exists
# 2. Run low-level agent for all assets
# 3. Log trading decisions
# 4. Apply risk management
# 5. Execute approved trades
# 6. Broadcast updates via ActionCable
#
class TradingCycleJob < ApplicationJob
  queue_as :trading

  def perform
    Rails.logger.info "[TradingCycle] Starting trading cycle..."

    cycle = TradingCycle.new
    decisions = cycle.execute

    actionable_count = decisions.count(&:actionable?)
    Rails.logger.info "[TradingCycle] Trading cycle complete: " \
                      "#{decisions.size} decisions, #{actionable_count} actionable"

    # Broadcast decisions via ActionCable
    broadcast_decisions(decisions)

    decisions
  end

  private

  def broadcast_decisions(decisions)
    decisions.each do |decision|
      DashboardChannel.broadcast_decision(decision)
    end
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Broadcast error: #{e.message}"
  end
end
