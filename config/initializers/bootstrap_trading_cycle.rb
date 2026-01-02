# frozen_string_literal: true

# Bootstrap the trading cycle chain on application startup
#
# This ensures the self-scheduling trading cycle starts immediately
# when the Rails application boots (not just when workers start).
#
# The trading cycle is self-scheduling: each run calculates market
# volatility and schedules the next run accordingly:
# - Very High volatility: 3 minute interval
# - High volatility: 6 minute interval
# - Medium volatility: 12 minute interval
# - Low volatility: 25 minute interval
#
# Skip bootstrap by setting SKIP_TRADING_BOOTSTRAP=true
#
Rails.application.config.after_initialize do
  # Skip in test environment
  next if Rails.env.test?

  # Skip in console or generators
  next if defined?(Rails::Console) || defined?(Rails::Generators)

  # Skip if explicitly disabled
  next if ENV["SKIP_TRADING_BOOTSTRAP"] == "true"

  # Delay slightly to allow workers to start
  Rails.logger.info "[Bootstrap] Queueing initial trading cycle bootstrap..."
  BootstrapTradingCycleJob.set(wait: 10.seconds).perform_later

  Rails.logger.info "[Bootstrap] Initial bootstrap queued (will run in 10 seconds)"
rescue StandardError => e
  Rails.logger.error "[Bootstrap] Failed to queue bootstrap job: #{e.message}"
end
