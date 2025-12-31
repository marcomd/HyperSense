# frozen_string_literal: true

module Costs
  # Main orchestrator for on-the-fly cost calculations
  #
  # Combines trading fees, LLM costs, and server costs into a unified
  # cost summary. All calculations are done on-the-fly without database
  # storage, using existing Position and TradingDecision records.
  #
  # @example Get cost summary for today
  #   calculator = Costs::Calculator.new
  #   summary = calculator.summary(period: :today)
  #   summary[:total_costs] # => 13.85 (USD)
  #
  # @example Calculate net P&L after fees
  #   net = calculator.net_pnl(period: :today)
  #   net[:net_realized_pnl] # => 144.77 (USD)
  #
  class Calculator
    # Valid period options for cost calculations
    VALID_PERIODS = %i[today week month all].freeze

    # Decimal precision for USD amounts
    USD_PRECISION = 2

    def initialize
      @trading_calculator = TradingFeeCalculator.new
      @llm_calculator = LLMCostCalculator.new
    end

    # Get complete cost summary for a period
    # @param period [Symbol] :today, :week, :month, or :all
    # @return [Hash] Cost breakdown with totals
    def summary(period: :today)
      validate_period!(period)

      since = period_start(period)

      trading = @trading_calculator.total_fees(since: since)
      llm = @llm_calculator.estimated_costs(since: since)
      server = calculate_server_cost(since: since)

      {
        period: period,
        period_start: since&.iso8601,
        trading_fees: trading,
        llm_costs: llm,
        server_cost: server,
        total_costs: (trading[:total] + llm[:total] + server[:prorated]).round(USD_PRECISION),
        breakdown: {
          trading: trading,
          llm: llm,
          server: server
        }
      }
    end

    # Calculate net P&L (gross P&L minus trading fees)
    # @param period [Symbol] :today, :week, :month, or :all
    # @return [Hash] Gross P&L, fees, and net P&L
    def net_pnl(period: :today)
      validate_period!(period)

      since = period_start(period)

      gross_realized = calculate_gross_realized_pnl(since: since)
      gross_unrealized = Position.open.sum(:unrealized_pnl).to_f.round(USD_PRECISION)
      trading_fees = @trading_calculator.total_fees(since: since)[:total]

      {
        gross_realized_pnl: gross_realized,
        gross_unrealized_pnl: gross_unrealized,
        trading_fees: trading_fees,
        net_realized_pnl: (gross_realized - trading_fees).round(USD_PRECISION),
        net_unrealized_pnl: gross_unrealized, # Fees not yet realized for open positions
        net_total_pnl: (gross_realized + gross_unrealized - trading_fees).round(USD_PRECISION)
      }
    end

    private

    # Validate period parameter
    # @param period [Symbol] Period to validate
    # @raise [ArgumentError] If period is invalid
    def validate_period!(period)
      return if VALID_PERIODS.include?(period)

      raise ArgumentError, "Invalid period: #{period}. Valid: #{VALID_PERIODS.join(', ')}"
    end

    # Convert period symbol to start time
    # @param period [Symbol] Period to convert
    # @return [Time, nil] Start time for the period (nil for :all)
    def period_start(period)
      case period
      when :today then Time.current.beginning_of_day
      when :week then 7.days.ago.beginning_of_day
      when :month then 30.days.ago.beginning_of_day
      when :all then nil
      end
    end

    # Calculate gross realized P&L from closed positions
    # @param since [Time, nil] Start of period
    # @return [Float] Total realized P&L
    def calculate_gross_realized_pnl(since:)
      scope = Position.closed
      scope = scope.where("closed_at >= ?", since) if since
      scope.sum(:realized_pnl).to_f.round(USD_PRECISION)
    end

    # Calculate prorated server cost for a period
    # @param since [Time, nil] Start of period
    # @return [Hash] Server cost breakdown
    def calculate_server_cost(since:)
      monthly = Settings.costs.server.monthly_cost.to_f
      daily = monthly / 30.0

      days = calculate_period_days(since)

      {
        monthly_rate: monthly,
        daily_rate: daily.round(4),
        days: days,
        prorated: (daily * days).round(USD_PRECISION)
      }
    end

    # Calculate number of days in period
    # @param since [Time, nil] Start of period
    # @return [Integer] Number of days
    def calculate_period_days(since)
      if since.nil?
        # For "all" period, calculate days since first activity
        first_record = earliest_record_time
        first_record ? ((Time.current - first_record) / 1.day).ceil : 0
      else
        ((Time.current - since) / 1.day).ceil
      end
    end

    # Find earliest record time across positions and decisions
    # @return [Time, nil] Earliest timestamp
    def earliest_record_time
      [
        Position.minimum(:opened_at),
        TradingDecision.minimum(:created_at)
      ].compact.min
    end
  end
end
