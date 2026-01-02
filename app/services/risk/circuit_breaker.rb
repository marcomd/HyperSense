# frozen_string_literal: true

module Risk
  # Circuit breaker to halt trading during excessive losses
  #
  # Monitors:
  # - Daily loss percentage (triggers if exceeds max_daily_loss)
  # - Consecutive losses (triggers if exceeds max_consecutive_losses)
  #
  # State is stored in Rails.cache with daily expiry for loss tracking.
  # Can be migrated to database model if persistence is needed.
  #
  # @example
  #   breaker = Risk::CircuitBreaker.new
  #
  #   # Check before trading
  #   unless breaker.trading_allowed?
  #     Rails.logger.warn "Circuit breaker active: #{breaker.trigger_reason}"
  #     return
  #   end
  #
  #   # After a losing trade
  #   breaker.record_loss(500)
  #   breaker.check_and_update!
  #
  #   # After a winning trade
  #   breaker.record_win(200)
  #
  class CircuitBreaker
    CACHE_KEY_PREFIX = "risk:circuit_breaker"

    # Default fallback values when Settings are not configured
    DEFAULT_MAX_DAILY_LOSS = 0.05
    DEFAULT_MAX_CONSECUTIVE_LOSSES = 3
    DEFAULT_COOLDOWN_HOURS = 24

    def initialize(account_manager: nil)
      @account_manager = account_manager || Execution::AccountManager.new
      @logger = Rails.logger
    end

    # Check if trading is currently allowed
    # @return [Boolean]
    def trading_allowed?
      return false if triggered?
      return false if cooldown_active?
      return false if daily_loss_exceeded?
      return false if consecutive_losses_exceeded?

      true
    end

    # Record a losing trade
    # @param amount [Numeric] Loss amount in dollars (positive number)
    def record_loss(amount)
      increment_daily_loss(amount.abs)
      increment_consecutive_losses
      @logger.info "[CircuitBreaker] Recorded loss: $#{amount.abs}"
    end

    # Record a winning trade (resets consecutive losses)
    # @param amount [Numeric] Win amount (for logging)
    def record_win(amount)
      reset_consecutive_losses
      @logger.info "[CircuitBreaker] Recorded win: $#{amount.abs}"
    end

    # Manually trigger the circuit breaker
    # @param reason [String] Trigger reason
    def trigger!(reason)
      Rails.cache.write(cache_key(:triggered), true, expires_in: cooldown_hours.hours)
      Rails.cache.write(cache_key(:trigger_reason), reason, expires_in: cooldown_hours.hours)
      Rails.cache.write(cache_key(:cooldown_until), cooldown_hours.hours.from_now, expires_in: cooldown_hours.hours)
      @logger.warn "[CircuitBreaker] TRIGGERED: #{reason}"
    end

    # Check thresholds and trigger if exceeded
    def check_and_update!
      if daily_loss_exceeded?
        trigger!("max_daily_loss")
      elsif consecutive_losses_exceeded?
        trigger!("consecutive_losses")
      end
    end

    # Reset all circuit breaker state
    def reset!
      %i[consecutive_losses triggered trigger_reason cooldown_until].each do |key|
        Rails.cache.delete(cache_key(key))
      end
      Rails.cache.delete(daily_loss_key)
      @logger.info "[CircuitBreaker] State reset"
    end

    # Current state summary
    # @return [Hash]
    def status
      {
        trading_allowed: trading_allowed?,
        daily_loss: daily_loss,
        daily_loss_pct: daily_loss_percentage,
        consecutive_losses: consecutive_losses,
        triggered: triggered?,
        trigger_reason: trigger_reason,
        cooldown_until: cooldown_until
      }
    end

    # Accessors for state

    def daily_loss
      # Use date-based key so it auto-expires at midnight
      Rails.cache.fetch(daily_loss_key, expires_in: time_until_midnight) { 0 }.to_f
    end

    def consecutive_losses
      Rails.cache.fetch(cache_key(:consecutive_losses)) { 0 }.to_i
    end

    def triggered?
      Rails.cache.read(cache_key(:triggered)) == true
    end

    def trigger_reason
      Rails.cache.read(cache_key(:trigger_reason))
    end

    def cooldown_until
      Rails.cache.read(cache_key(:cooldown_until))
    end

    private

    def increment_daily_loss(amount)
      current = daily_loss
      Rails.cache.write(daily_loss_key, current + amount, expires_in: time_until_midnight)
    end

    def increment_consecutive_losses
      current = consecutive_losses
      Rails.cache.write(cache_key(:consecutive_losses), current + 1)
    end

    def reset_consecutive_losses
      Rails.cache.write(cache_key(:consecutive_losses), 0)
    end

    def daily_loss_exceeded?
      daily_loss_percentage >= max_daily_loss_pct
    end

    def consecutive_losses_exceeded?
      consecutive_losses >= max_consecutive_losses
    end

    def cooldown_active?
      until_time = cooldown_until
      return false unless until_time

      Time.current < until_time
    end

    def daily_loss_percentage
      account_value = fetch_account_value
      return 0 if account_value.nil? || account_value.zero?

      (daily_loss / account_value).to_f
    end

    def fetch_account_value
      state = @account_manager.fetch_account_state
      state[:account_value]
    rescue StandardError => e
      @logger.error "[CircuitBreaker] Failed to fetch account value: #{e.message}"
      nil
    end

    def cache_key(key)
      "#{CACHE_KEY_PREFIX}:#{key}"
    end

    def daily_loss_key
      # Date-based key so it auto-expires at midnight
      "#{CACHE_KEY_PREFIX}:daily_loss:#{Date.current}"
    end

    def time_until_midnight
      (Date.tomorrow.beginning_of_day - Time.current).seconds
    end

    # Settings

    def max_daily_loss_pct
      Settings.risk.max_daily_loss || DEFAULT_MAX_DAILY_LOSS
    end

    def max_consecutive_losses
      Settings.risk.max_consecutive_losses || DEFAULT_MAX_CONSECUTIVE_LOSSES
    end

    def cooldown_hours
      Settings.risk.circuit_breaker_cooldown || DEFAULT_COOLDOWN_HOURS
    end
  end
end
