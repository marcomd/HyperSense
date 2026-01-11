# frozen_string_literal: true

module Risk
  # Provides profile-aware risk parameters for the trading system.
  #
  # This service reads the current risk profile from the database and returns
  # the corresponding parameters from settings.yml. It centralizes all profile
  # parameter access to ensure consistent behavior across the system.
  #
  # @example Get current profile parameters
  #   Risk::ProfileService.current_params  # => { rsi_oversold: 30, ... }
  #   Risk::ProfileService.rsi_oversold    # => 30
  #   Risk::ProfileService.min_confidence  # => 0.6
  #
  # @example Get profile description for LLM context
  #   Risk::ProfileService.profile_description
  #   # => "MODERATE: Balanced risk profile - standard entry criteria and leverage"
  #
  class ProfileService
    class << self
      # Returns all parameters for the current profile as a hash.
      #
      # @return [Hash] profile parameters with symbol keys
      def current_params
        profile_name = RiskProfile.current_name
        Settings.risk_profiles.send(profile_name).to_h.with_indifferent_access
      end

      # RSI oversold threshold (price may be undervalued).
      # @return [Integer]
      def rsi_oversold
        current_params[:rsi_oversold]
      end

      # RSI overbought threshold (price may be overvalued).
      # @return [Integer]
      def rsi_overbought
        current_params[:rsi_overbought]
      end

      # RSI threshold for waiting on long entries.
      # Wait for RSI below this before opening long.
      # @return [Integer]
      def rsi_pullback_threshold
        current_params[:rsi_pullback_threshold]
      end

      # RSI threshold for waiting on short entries.
      # Wait for RSI above this before opening short.
      # @return [Integer]
      def rsi_bounce_threshold
        current_params[:rsi_bounce_threshold]
      end

      # Minimum risk/reward ratio required for trades.
      # @return [Float]
      def min_risk_reward_ratio
        current_params[:min_risk_reward_ratio]
      end

      # Minimum confidence score required to execute trades.
      # @return [Float]
      def min_confidence
        current_params[:min_confidence]
      end

      # Maximum position size as percentage of capital.
      # @return [Float]
      def max_position_size
        current_params[:max_position_size]
      end

      # Default leverage for new positions.
      # @return [Integer]
      def default_leverage
        current_params[:default_leverage]
      end

      # Maximum number of concurrent open positions.
      # @return [Integer]
      def max_open_positions
        current_params[:max_open_positions]
      end

      # Take-profit zone threshold as decimal (e.g., 0.02 = 2%).
      # When price is within this percentage of TP, agent should consider closing.
      # @return [Float]
      def tp_zone_pct
        current_params[:tp_zone_pct] || 0.02
      end

      # Profit drawdown alert threshold as decimal (e.g., 0.30 = 30%).
      # Alert when this percentage of peak profit has been lost.
      # @return [Float]
      def profit_drawdown_alert_pct
        current_params[:profit_drawdown_alert_pct] || 0.30
      end

      # Whether trailing stop is enabled for current profile.
      # @return [Boolean]
      def trailing_stop_enabled?
        current_params.dig(:trailing_stop, :enabled) || false
      end

      # Profit threshold to activate trailing stop as decimal (e.g., 0.015 = 1.5%).
      # Trailing stop activates when position reaches this profit level.
      # @return [Float]
      def trailing_stop_activation_pct
        current_params.dig(:trailing_stop, :activation_profit_pct) || 0.015
      end

      # Distance trailing stop follows behind peak price as decimal (e.g., 0.01 = 1%).
      # Stop-loss is set to (peak_price - trail_distance) for longs.
      # @return [Float]
      def trailing_stop_trail_distance_pct
        current_params.dig(:trailing_stop, :trail_distance_pct) || 0.01
      end

      # Returns the name of the current profile.
      # @return [String]
      def current_name
        RiskProfile.current_name
      end

      # Returns a human-readable description of the current profile.
      # Used to inform the LLM about the active trading style.
      #
      # @return [String] profile description
      def profile_description
        case current_name
        when "cautious"
          "CAUTIOUS: Conservative risk profile - fewer trades, stricter entry criteria, lower leverage"
        when "fearless"
          "FEARLESS: Aggressive risk profile - more trades, relaxed entry criteria, higher leverage"
        else
          "MODERATE: Balanced risk profile - standard entry criteria and leverage"
        end
      end
    end
  end
end
