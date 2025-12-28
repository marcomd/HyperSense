# frozen_string_literal: true

# Main orchestrator for the trading cycle
#
# Coordinates the entire trading workflow:
# 1. Check circuit breaker (halt if triggered)
# 2. Sync positions from Hyperliquid
# 3. Check/refresh macro strategy
# 4. Run low-level agent for all assets
# 5. Filter and approve decisions (using RiskManager)
# 6. Execute approved trades
#
# @example
#   cycle = TradingCycle.new
#   decisions = cycle.execute
#   # => [TradingDecision(BTC, hold), TradingDecision(ETH, open)]
#
class TradingCycle
  # Initialize the trading cycle with all required dependencies
  #
  # @return [TradingCycle] A new instance of TradingCycle
  def initialize
    @logger = Rails.logger
    @position_manager = Execution::PositionManager.new
    @account_manager = Execution::AccountManager.new
    @order_executor = Execution::OrderExecutor.new
    @risk_manager = Risk::RiskManager.new
    @position_sizer = Risk::PositionSizer.new
    @circuit_breaker = Risk::CircuitBreaker.new
  end

  # Execute the full trading cycle
  #
  # @return [Array<TradingDecision>] Array of decisions made (empty if circuit breaker active)
  # @example
  #   cycle.execute
  #   # => [#<TradingDecision symbol: "BTC", operation: "hold", confidence: 0.45>]
  def execute
    @logger.info "[TradingCycle] Starting execution..."

    # Step 0: Check circuit breaker
    unless @circuit_breaker.trading_allowed?
      @logger.warn "[TradingCycle] Circuit breaker active: #{@circuit_breaker.trigger_reason}"
      return []
    end

    # Step 1: Sync positions from Hyperliquid (if configured)
    sync_positions_if_configured

    # Step 2: Ensure we have a valid macro strategy
    ensure_macro_strategy

    # Step 3: Get current macro strategy
    macro_strategy = MacroStrategy.active
    @logger.info "[TradingCycle] Using macro strategy: #{macro_strategy&.bias || 'none'}"

    # Step 4: Run low-level agent for all assets
    decisions = run_low_level_agent(macro_strategy)

    # Step 5: Log decisions
    log_decisions(decisions)

    # Step 6: Filter and approve actionable decisions
    approved = filter_and_approve(decisions)

    # Step 7: Execute approved trades
    execute_decisions(approved)

    @logger.info "[TradingCycle] Execution complete"
    decisions
  end

  private

  # Sync positions from Hyperliquid if client is configured
  #
  # Fetches current positions from the exchange and updates local database.
  # Silently handles API errors to avoid disrupting the trading cycle.
  #
  # @return [void]
  def sync_positions_if_configured
    client = Execution::HyperliquidClient.new
    return unless client.configured?

    @logger.info "[TradingCycle] Syncing positions from Hyperliquid..."
    @position_manager.sync_from_hyperliquid
    @position_manager.update_prices
  rescue Execution::HyperliquidClient::HyperliquidApiError => e
    @logger.warn "[TradingCycle] Position sync failed: #{e.message}"
  end

  # Ensure we have a valid macro strategy, refresh if needed
  #
  # Checks if the current macro strategy is stale or missing and triggers
  # a synchronous refresh via MacroStrategyJob if necessary.
  #
  # @return [void]
  def ensure_macro_strategy
    return unless MacroStrategy.needs_refresh?

    @logger.info "[TradingCycle] Macro strategy needs refresh, triggering job..."
    MacroStrategyJob.perform_now
  end

  # Run low-level agent for all configured assets
  # @param macro_strategy [MacroStrategy, nil] Current macro strategy
  # @return [Array<TradingDecision>] Array of decisions
  def run_low_level_agent(macro_strategy)
    @logger.info "[TradingCycle] Running low-level agent..."

    agent = Reasoning::LowLevelAgent.new
    agent.decide_all(macro_strategy: macro_strategy)
  end

  # Log summary of decisions
  # @param decisions [Array<TradingDecision>] Decisions to log
  def log_decisions(decisions)
    decisions.each do |decision|
      @logger.info "[TradingCycle] #{decision.symbol}: #{decision.operation} " \
                   "(confidence: #{decision.confidence}, status: #{decision.status})"
    end

    actionable = decisions.select(&:actionable?)
    holds = decisions.select(&:hold?)

    @logger.info "[TradingCycle] Summary: #{actionable.size} actionable, #{holds.size} holds out of #{decisions.size} total"
  end

  # Filter decisions through risk checks and approve valid ones
  # Uses Risk::RiskManager for centralized validation
  # @param decisions [Array<TradingDecision>] Decisions to filter
  # @return [Array<TradingDecision>] Approved decisions
  def filter_and_approve(decisions)
    decisions.select do |decision|
      next false unless decision.actionable?
      next false unless decision.status == "pending"

      # Get current price for validation
      entry_price = fetch_current_price(decision.symbol)
      unless entry_price
        decision.reject!("Could not fetch price for #{decision.symbol}")
        next false
      end

      # Use RiskManager for centralized validation
      result = @risk_manager.validate(decision, entry_price: entry_price)
      unless result.approved?
        decision.reject!(result.rejection_reason)
        next false
      end

      # For open operations, calculate optimal position size
      if decision.operation == "open" && decision.stop_loss
        sizing = @position_sizer.optimal_size_for_decision(decision, entry_price: entry_price)
        if sizing
          @logger.info "[TradingCycle] Position sizing for #{decision.symbol}: #{sizing[:size]} " \
                       "(risk: $#{sizing[:risk_amount]}#{sizing[:capped] ? ', capped' : ''})"
        end
      end

      decision.approve!
      @logger.info "[TradingCycle] Approved: #{decision.symbol} #{decision.operation}"
      true
    end
  end

  # Execute approved decisions
  # @param approved_decisions [Array<TradingDecision>] Decisions to execute
  def execute_decisions(approved_decisions)
    return if approved_decisions.empty?

    @logger.info "[TradingCycle] Executing #{approved_decisions.size} approved decisions..."

    approved_decisions.each do |decision|
      @logger.info "[TradingCycle] Executing #{decision.symbol} #{decision.operation}..."

      begin
        order = @order_executor.execute(decision)

        if order
          @logger.info "[TradingCycle] #{decision.symbol}: Order #{order.id} #{order.status}"
        else
          @logger.warn "[TradingCycle] #{decision.symbol}: Execution returned nil"
        end
      rescue Execution::HyperliquidClient::WriteOperationNotImplemented => e
        @logger.warn "[TradingCycle] #{decision.symbol}: #{e.message}"
      rescue StandardError => e
        @logger.error "[TradingCycle] #{decision.symbol}: Execution failed - #{e.message}"
      end
    end

    log_execution_summary(approved_decisions)
  end

  # Log execution results summary
  #
  # @param decisions [Array<TradingDecision>] Executed decisions
  # @return [void]
  def log_execution_summary(decisions)
    executed = decisions.count(&:executed?)
    failed = decisions.count { |d| d.status == "failed" }

    @logger.info "[TradingCycle] Execution summary: #{executed} executed, #{failed} failed"

    if Settings.trading.paper_trading
      @logger.info "[TradingCycle] Paper trading mode - no real orders submitted"
    end
  end

  # Get current portfolio state including open positions and PnL
  #
  # @return [Hash] Portfolio state with keys :positions, :open_count, :total_unrealized_pnl
  # @example
  #   current_portfolio
  #   # => { positions: [Position], open_count: 2, total_unrealized_pnl: 150.50 }
  def current_portfolio
    {
      positions: Position.open.to_a,
      open_count: Position.open.count,
      total_unrealized_pnl: Position.open.sum(:unrealized_pnl)
    }
  end

  # Fetch current price for a symbol
  # @param symbol [String] Asset symbol
  # @return [BigDecimal, nil] Current price or nil
  def fetch_current_price(symbol)
    client = Execution::HyperliquidClient.new
    mids = client.all_mids
    mids[symbol]&.to_d
  rescue StandardError => e
    @logger.warn "[TradingCycle] Failed to fetch price for #{symbol}: #{e.message}"
    nil
  end
end
