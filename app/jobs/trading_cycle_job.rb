# frozen_string_literal: true

# Main trading cycle job - orchestrates the entire trading workflow
#
# Self-scheduling job that adjusts frequency based on market volatility:
# - Very High volatility (ATR >= 3%): 3 minute interval
# - High volatility (ATR >= 2%): 6 minute interval
# - Medium volatility (ATR >= 1%): 12 minute interval
# - Low volatility (ATR < 1%): 25 minute interval
#
# The job schedules ForecastJob to run 1 minute before each cycle
# to ensure fresh forecasts are available for trading decisions.
#
# @example Manual trigger
#   TradingCycleJob.perform_later
#
class TradingCycleJob < ApplicationJob
  queue_as :trading

  # Default interval when volatility cannot be determined (minutes)
  DEFAULT_INTERVAL = 12

  # Minimum interval between cycles (minutes)
  MIN_INTERVAL = 3

  # Maximum interval between cycles (minutes)
  MAX_INTERVAL = 25

  def perform
    Rails.logger.info "[TradingCycle] Starting trading cycle..."

    cycle = TradingCycle.new
    decisions = cycle.execute

    # Calculate volatility for next cycle
    volatility = calculate_volatility

    # Update decisions with volatility data
    update_decisions_with_volatility(decisions, volatility)

    actionable_count = decisions.count(&:actionable?)
    Rails.logger.info "[TradingCycle] Trading cycle complete: " \
                      "#{decisions.size} decisions, #{actionable_count} actionable, " \
                      "volatility: #{volatility.level}, next cycle: #{volatility.interval}m"

    # Broadcast decisions via ActionCable
    broadcast_decisions(decisions)

    decisions
  ensure
    # Always schedule next cycle, even on error
    schedule_next_cycle
  end

  private

  # Calculate current market volatility
  #
  # @return [Indicators::VolatilityClassifier::Result]
  def calculate_volatility
    Indicators::VolatilityClassifier.classify_all_assets
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Volatility calculation failed: #{e.message}"
    default_volatility_result
  end

  # Default result when volatility cannot be determined
  #
  # @return [Indicators::VolatilityClassifier::Result]
  def default_volatility_result
    Indicators::VolatilityClassifier::Result.new(
      level: :medium,
      interval: DEFAULT_INTERVAL,
      atr_value: nil,
      atr_percentage: nil
    )
  end

  # Update trading decisions with volatility information
  #
  # @param decisions [Array<TradingDecision>]
  # @param volatility [Indicators::VolatilityClassifier::Result]
  def update_decisions_with_volatility(decisions, volatility)
    decisions.each do |decision|
      decision.update!(
        volatility_level: volatility.level,
        atr_value: volatility.atr_percentage,
        next_cycle_interval: volatility.interval
      )
    end
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Failed to update volatility: #{e.message}"
  end

  # Schedule next trading cycle based on volatility
  #
  # Also schedules ForecastJob to run 1 minute before the next cycle
  # to ensure fresh forecasts are available for trading decisions.
  def schedule_next_cycle
    volatility = calculate_volatility
    interval = volatility.interval.clamp(MIN_INTERVAL, MAX_INTERVAL)

    Rails.logger.info "[TradingCycle] Scheduling next cycle in #{interval} minutes " \
                      "(volatility: #{volatility.level})"

    # Schedule ForecastJob 1 minute before trading cycle
    schedule_forecast_job(interval)

    # Schedule next trading cycle
    TradingCycleJob.set(wait: interval.minutes).perform_later
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Failed to schedule next cycle: #{e.message}"
    # Fallback to default interval on scheduling error
    TradingCycleJob.set(wait: DEFAULT_INTERVAL.minutes).perform_later
  end

  # Schedule ForecastJob to run before the next trading cycle
  #
  # @param interval [Integer] Trading cycle interval in minutes
  def schedule_forecast_job(interval)
    forecast_wait = interval - 1
    return unless forecast_wait.positive?

    ForecastJob.set(wait: forecast_wait.minutes).perform_later
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Failed to schedule forecast: #{e.message}"
  end

  # Broadcast decisions via ActionCable
  #
  # @param decisions [Array<TradingDecision>]
  def broadcast_decisions(decisions)
    decisions.each do |decision|
      DashboardChannel.broadcast_decision(decision)
    end
  rescue StandardError => e
    Rails.logger.error "[TradingCycle] Broadcast error: #{e.message}"
  end
end
