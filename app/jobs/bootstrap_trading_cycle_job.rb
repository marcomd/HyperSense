# frozen_string_literal: true

# Bootstrap job to ensure the trading cycle chain is running
#
# This job runs on a fixed schedule (every 30 minutes) as a safety net.
# It checks if a TradingCycleJob is already scheduled and starts the
# chain if not.
#
# The trading cycle is self-scheduling (each run schedules the next),
# but this bootstrap ensures the chain restarts after:
# - Application restart
# - Worker crash
# - All jobs failing
#
# @example Manual trigger
#   BootstrapTradingCycleJob.perform_later
#
class BootstrapTradingCycleJob < ApplicationJob
  queue_as :trading

  def perform
    if trading_cycle_scheduled?
      Rails.logger.info "[Bootstrap] Trading cycle already scheduled, skipping"
      return
    end

    Rails.logger.info "[Bootstrap] No trading cycle found, starting chain..."

    # Schedule immediate trading cycle
    TradingCycleJob.perform_later

    Rails.logger.info "[Bootstrap] Trading cycle chain started"
  end

  private

  # Check if a TradingCycleJob is already scheduled or running
  #
  # Checks the Solid Queue tables for any pending TradingCycleJob.
  #
  # @return [Boolean] true if a TradingCycleJob is pending
  def trading_cycle_scheduled?
    SolidQueue::Job.where(class_name: "TradingCycleJob")
                   .where(finished_at: nil)
                   .exists?
  rescue StandardError => e
    Rails.logger.warn "[Bootstrap] Could not check job status: #{e.message}"
    false
  end
end
