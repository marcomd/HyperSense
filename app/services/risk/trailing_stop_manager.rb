# frozen_string_literal: true

module Risk
  # Manages trailing stops for open positions.
  #
  # A trailing stop is a dynamic stop-loss that moves up (for longs) or down (for shorts)
  # as the position becomes profitable. This locks in profits while still allowing
  # the position to capture further gains.
  #
  # How it works:
  # 1. Trailing stop activates when position profit reaches activation threshold
  # 2. Stop-loss is set to (peak_price - trail_distance) for longs
  # 3. As price rises and sets new peak, stop-loss follows
  # 4. Stop-loss NEVER moves backward - only forward to lock in more profit
  #
  # Settings are profile-specific (cautious/moderate/fearless) to match risk tolerance.
  #
  # @example
  #   manager = Risk::TrailingStopManager.new
  #   results = manager.check_all_positions
  #   # => { updated: 3, activated: 1, skipped: 5 }
  #
  class TrailingStopManager
    def initialize
      @profile = ProfileService
      @logger = Rails.logger
    end

    # Check and update trailing stops for all open positions.
    # Called periodically by RiskMonitoringJob.
    # @return [Hash] Results summary
    def check_all_positions
      results = { updated: 0, activated: 0, skipped: 0 }

      unless @profile.trailing_stop_enabled?
        @logger.debug "[TrailingStop] Disabled for current profile (#{@profile.current_name})"
        return results
      end

      Position.open.find_each do |position|
        result = process_position(position)
        case result
        when :activated then results[:activated] += 1
        when :updated then results[:updated] += 1
        else results[:skipped] += 1
        end
      end

      log_results(results)
      results
    end

    private

    # Process a single position for trailing stop.
    # @param position [Position] Position to check
    # @return [Symbol] :activated, :updated, or :skipped
    def process_position(position)
      # Skip if no peak price tracked yet
      unless position.peak_price
        @logger.debug "[TrailingStop] #{position.symbol}: No peak tracked yet"
        return :skipped
      end

      # Calculate current profit percentage
      profit_pct = position.pnl_percent / 100.0 # Convert to decimal

      # Check if trailing stop should activate
      activation_threshold = @profile.trailing_stop_activation_pct

      unless position.trailing_stop_active?
        if profit_pct >= activation_threshold
          activate_trailing_stop(position)
          return :activated
        else
          @logger.debug "[TrailingStop] #{position.symbol}: Profit #{(profit_pct * 100).round(2)}% " \
                        "below activation threshold #{(activation_threshold * 100).round(2)}%"
          return :skipped
        end
      end

      # Trailing stop is active - check if we should move SL
      update_trailing_stop(position) ? :updated : :skipped
    end

    # Activate trailing stop for a position.
    # Saves original stop-loss and marks trailing stop as active.
    # @param position [Position] Position to activate trailing stop for
    def activate_trailing_stop(position)
      position.update!(
        trailing_stop_active: true,
        original_stop_loss_price: position.stop_loss_price
      )

      @logger.info "[TrailingStop] ACTIVATED for #{position.symbol} at #{position.pnl_percent.round(2)}% profit"

      # Immediately update the stop-loss
      update_trailing_stop(position)
    end

    # Update stop-loss based on peak price and trail distance.
    # @param position [Position] Position to update
    # @return [Boolean] true if SL was updated
    def update_trailing_stop(position)
      trail_distance = @profile.trailing_stop_trail_distance_pct

      new_sl = if position.long?
        # For longs: SL trails below peak price
        position.peak_price * (1 - trail_distance)
      else
        # For shorts: SL trails above peak price
        position.peak_price * (1 + trail_distance)
      end

      current_sl = position.stop_loss_price

      # Only move SL in profitable direction (up for longs, down for shorts)
      should_update = if position.long?
        current_sl.nil? || new_sl > current_sl
      else
        current_sl.nil? || new_sl < current_sl
      end

      if should_update
        old_sl = current_sl
        position.update!(stop_loss_price: new_sl)

        @logger.info "[TrailingStop] #{position.symbol}: SL moved from #{format_price(old_sl)} " \
                     "to #{format_price(new_sl)} (trailing peak #{format_price(position.peak_price)})"
        true
      else
        false
      end
    end

    # Format price for logging.
    # @param price [Numeric, nil] Price to format
    # @return [String] Formatted price string
    def format_price(price)
      price ? "$#{price.to_f.round(2)}" : "N/A"
    end

    # Log results summary.
    # @param results [Hash] Results from check_all_positions
    def log_results(results)
      if results[:activated].positive? || results[:updated].positive?
        @logger.info "[TrailingStop] #{results[:activated]} activated, #{results[:updated]} updated, " \
                     "#{results[:skipped]} skipped"
      else
        @logger.debug "[TrailingStop] No trailing stop updates (#{results[:skipped]} positions checked)"
      end
    end
  end
end
