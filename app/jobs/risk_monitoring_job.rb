# frozen_string_literal: true

# Background job for continuous risk monitoring
#
# Runs every minute via Solid Queue to:
# - Check all open positions for stop-loss/take-profit triggers
# - Update circuit breaker metrics
# - Log monitoring summary
#
# Schedule configured in config/recurring.yml:
#   risk_monitoring:
#     class: RiskMonitoringJob
#     schedule: every 1 minute
#
class RiskMonitoringJob < ApplicationJob
  queue_as :default

  def perform
    logger.info "[RiskMonitoringJob] Starting risk monitoring cycle"

    stop_loss_results = check_stop_loss_take_profit
    circuit_breaker_status = update_circuit_breaker

    log_summary(stop_loss_results, circuit_breaker_status)

    {
      stop_loss_results: stop_loss_results,
      circuit_breaker_status: circuit_breaker_status
    }
  end

  private

  def check_stop_loss_take_profit
    stop_loss_manager = Risk::StopLossManager.new
    results = stop_loss_manager.check_all_positions

    if results[:triggered].any?
      logger.info "[RiskMonitoringJob] Triggered #{results[:triggered].size} SL/TP orders"
    end

    results
  end

  def update_circuit_breaker
    circuit_breaker = Risk::CircuitBreaker.new
    circuit_breaker.check_and_update!

    status = circuit_breaker.status

    if status[:triggered]
      logger.warn "[RiskMonitoringJob] Circuit breaker active: #{status[:trigger_reason]}"
    end

    status
  end

  def log_summary(stop_loss_results, circuit_breaker_status)
    logger.info "[RiskMonitoringJob] Summary: " \
                "Positions checked=#{stop_loss_results[:checked]}, " \
                "Triggers=#{stop_loss_results[:triggered].size}, " \
                "Trading allowed=#{circuit_breaker_status[:trading_allowed]}"
  end
end
