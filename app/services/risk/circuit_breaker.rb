# frozen_string_literal: true

module Risk
  # Circuit breaker to halt trading during excessive losses
  #
  # Monitors:
  # - Daily loss percentage (triggers if exceeds max_daily_loss)
  # - Consecutive losses (triggers if exceeds max_consecutive_losses)
  #
  # When thresholds are exceeded, automatically sets TradingMode to "exit_only".
  # User can override by switching back to "enabled" via the dashboard.
  #
  # Loss tracking is stored in Rails.cache with daily expiry.
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

    def initialize(account_manager: nil)
      @account_manager = account_manager || Execution::AccountManager.new
      @logger = Rails.logger
    end

    # Check if opening new positions is currently allowed
    # @return [Boolean]
    def trading_allowed?
      TradingMode.current.can_open?
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

    # Trigger the circuit breaker by setting TradingMode to exit_only
    # @param reason [String] Trigger reason (e.g., "max_daily_loss", "consecutive_losses")
    def trigger!(reason)
      human_reason = format_reason(reason)
      TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker", reason: human_reason)

      # Broadcast via WebSocket for real-time dashboard update
      DashboardChannel.broadcast_trading_mode_update(TradingMode.current)

      @logger.warn "[CircuitBreaker] TRIGGERED: #{reason} - Trading mode set to exit_only"
    end

    # Check thresholds and trigger if exceeded
    # Only triggers if TradingMode is currently "enabled" (user hasn't manually blocked/limited)
    def check_and_update!
      # Don't trigger if mode is already exit_only or blocked
      return unless TradingMode.current_mode == "enabled"

      if daily_loss_exceeded?
        trigger!("max_daily_loss")
      elsif consecutive_losses_exceeded?
        trigger!("consecutive_losses")
      end
    end

    # Reset all circuit breaker state and set TradingMode back to enabled
    def reset!
      Rails.cache.delete(cache_key(:consecutive_losses))
      Rails.cache.delete(daily_loss_key)
      TradingMode.switch_to!("enabled", changed_by: "system", reason: nil)
      @logger.info "[CircuitBreaker] State reset - Trading mode set to enabled"
    end

    # Current state summary
    # @return [Hash]
    def status
      mode = TradingMode.current
      {
        trading_allowed: trading_allowed?,
        daily_loss: daily_loss,
        daily_loss_pct: daily_loss_percentage,
        consecutive_losses: consecutive_losses,
        triggered: triggered?,
        trigger_reason: trigger_reason,
        trading_mode: mode.mode,
        trading_mode_changed_by: mode.changed_by
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

    # Returns true if circuit breaker has triggered (mode is exit_only and changed_by is circuit_breaker)
    def triggered?
      mode = TradingMode.current
      mode.mode == "exit_only" && mode.changed_by == "circuit_breaker"
    end

    # Returns the reason for the current trading mode restriction
    def trigger_reason
      mode = TradingMode.current
      mode.reason if mode.mode != "enabled"
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

    # Format trigger reason for human-readable display
    def format_reason(reason)
      case reason
      when "max_daily_loss"
        "Daily loss exceeded #{(max_daily_loss_pct * 100).round(1)}%"
      when "consecutive_losses"
        "#{max_consecutive_losses} consecutive losing trades"
      else
        reason
      end
    end
  end
end
