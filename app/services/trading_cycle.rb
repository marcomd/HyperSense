# frozen_string_literal: true

# Main orchestrator for the trading cycle
#
# Coordinates the entire trading workflow:
# 1. Sync positions from Hyperliquid
# 2. Check/refresh macro strategy
# 3. Run low-level agent for all assets
# 4. Filter and approve decisions
# 5. Execute approved trades
#
class TradingCycle
  def initialize
    @logger = Rails.logger
    @position_manager = Execution::PositionManager.new
    @account_manager = Execution::AccountManager.new
    @order_executor = Execution::OrderExecutor.new
  end

  # Execute the full trading cycle
  # @return [Array<TradingDecision>] Array of decisions made
  def execute
    @logger.info "[TradingCycle] Starting execution..."

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

  # Filter decisions through basic risk checks and approve valid ones
  # @param decisions [Array<TradingDecision>] Decisions to filter
  # @return [Array<TradingDecision>] Approved decisions
  def filter_and_approve(decisions)
    decisions.select do |decision|
      next false unless decision.actionable?
      next false unless decision.status == "pending"

      # Check confidence threshold
      min_confidence = Settings.risk.min_confidence
      if decision.confidence && decision.confidence < min_confidence
        decision.reject!("Confidence #{decision.confidence} below minimum #{min_confidence}")
        next false
      end

      # Check position limits for open operations
      if decision.operation == "open"
        if Position.open.count >= Settings.risk.max_open_positions
          decision.reject!("Maximum open positions (#{Settings.risk.max_open_positions}) reached")
          next false
        end

        if @position_manager.has_open_position?(decision.symbol)
          decision.reject!("Already have open position for #{decision.symbol}")
          next false
        end
      end

      # Check for existing position for close operations
      if decision.operation == "close"
        unless @position_manager.has_open_position?(decision.symbol)
          decision.reject!("No open position for #{decision.symbol}")
          next false
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

  # Log execution results
  # @param decisions [Array<TradingDecision>] Executed decisions
  def log_execution_summary(decisions)
    executed = decisions.count(&:executed?)
    failed = decisions.count { |d| d.status == "failed" }

    @logger.info "[TradingCycle] Execution summary: #{executed} executed, #{failed} failed"

    if Settings.trading.paper_trading
      @logger.info "[TradingCycle] Paper trading mode - no real orders submitted"
    end
  end

  # Get current portfolio state
  # @return [Hash] Portfolio state
  def current_portfolio
    {
      positions: Position.open.to_a,
      open_count: Position.open.count,
      total_unrealized_pnl: Position.open.sum(:unrealized_pnl)
    }
  end
end
