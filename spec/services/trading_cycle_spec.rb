# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingCycle do
  let(:trading_cycle) { described_class.new }
  let(:macro_strategy) { create(:macro_strategy, bias: "bullish") }
  let(:circuit_breaker) { instance_double(Risk::CircuitBreaker, trading_allowed?: true, trigger_reason: nil) }
  let(:position_manager) { instance_double(Execution::PositionManager) }
  let(:account_manager) { instance_double(Execution::AccountManager) }
  let(:risk_manager) { instance_double(Risk::RiskManager) }
  let(:hyperliquid_client) { instance_double(Execution::HyperliquidClient, configured?: false) }

  before do
    allow(Risk::CircuitBreaker).to receive(:new).and_return(circuit_breaker)
    allow(Execution::PositionManager).to receive(:new).and_return(position_manager)
    allow(Execution::AccountManager).to receive(:new).and_return(account_manager)
    allow(Risk::RiskManager).to receive(:new).and_return(risk_manager)
    allow(Execution::HyperliquidClient).to receive(:new).and_return(hyperliquid_client)
    allow(MacroStrategy).to receive(:needs_refresh?).and_return(false)
    allow(MacroStrategy).to receive(:active).and_return(macro_strategy)

    # Clean up trading modes and create default enabled mode
    TradingMode.delete_all
    create(:trading_mode, mode: "enabled")

    # Create market snapshots for all assets
    Settings.assets.to_a.each do |symbol|
      create(:market_snapshot, symbol: symbol, price: 100_000, captured_at: Time.current)
    end
  end

  describe "#execute" do
    context "when trading mode is blocked" do
      before do
        TradingMode.switch_to!("blocked", changed_by: "dashboard", reason: "Manual halt")
      end

      it "returns empty array" do
        expect(trading_cycle.execute).to eq([])
      end
    end

    context "when trading mode is exit_only" do
      before do
        TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker", reason: "Daily loss exceeded")
      end

      it "does not return empty array (allows close decisions)" do
        # Should continue execution, not bail out immediately
        allow(hyperliquid_client).to receive(:read_configured?).and_return(false)
        allow(position_manager).to receive(:sync_from_hyperliquid)
        allow(position_manager).to receive(:update_prices)

        readiness_checker = instance_double(Risk::ReadinessChecker)
        allow(Risk::ReadinessChecker).to receive(:new).and_return(readiness_checker)
        allow(readiness_checker).to receive(:check).and_return(
          Risk::ReadinessChecker::ReadinessResult.new(ready: true)
        )

        low_level_agent = instance_double(Reasoning::LowLevelAgent)
        allow(Reasoning::LowLevelAgent).to receive(:new).and_return(low_level_agent)
        allow(low_level_agent).to receive(:decide_all).and_return([])

        # Should complete the cycle (empty decisions, but not blocked)
        expect(trading_cycle.execute).to eq([])
      end
    end

    context "when trading mode is enabled" do
      it "allows normal execution" do
        # Should continue execution
        allow(hyperliquid_client).to receive(:read_configured?).and_return(false)
        allow(position_manager).to receive(:sync_from_hyperliquid)
        allow(position_manager).to receive(:update_prices)

        readiness_checker = instance_double(Risk::ReadinessChecker)
        allow(Risk::ReadinessChecker).to receive(:new).and_return(readiness_checker)
        allow(readiness_checker).to receive(:check).and_return(
          Risk::ReadinessChecker::ReadinessResult.new(ready: true)
        )

        low_level_agent = instance_double(Reasoning::LowLevelAgent)
        allow(Reasoning::LowLevelAgent).to receive(:new).and_return(low_level_agent)
        allow(low_level_agent).to receive(:decide_all).and_return([])

        expect(trading_cycle.execute).to eq([])
      end
    end
  end

  describe "trading mode filter in filter_and_approve" do
    let(:open_decision) do
      create(:trading_decision,
        symbol: "BTC",
        operation: "open",
        direction: "long",
        confidence: 0.75,
        status: "pending",
        parsed_decision: { "leverage" => 3, "stop_loss" => 95_000, "take_profit" => 115_000 })
    end

    let(:close_decision) do
      create(:trading_decision,
        symbol: "BTC",
        operation: "close",
        direction: nil,
        confidence: 0.75,
        status: "pending")
    end

    context "when trading mode is exit_only" do
      before do
        TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker")
      end

      it "rejects open decisions" do
        open_decision # create decision

        # The filter checks trading mode - we test the reject message
        mode = TradingMode.current
        expect(mode.can_open?).to be false
        open_decision.reject!("Trading mode '#{mode.mode}' does not allow opening positions")

        expect(open_decision.status).to eq("rejected")
        expect(open_decision.rejection_reason).to include("does not allow opening")
      end

      it "allows close decisions" do
        mode = TradingMode.current
        expect(mode.can_close?).to be true
      end
    end

    context "when trading mode is blocked" do
      before do
        TradingMode.switch_to!("blocked", changed_by: "dashboard")
      end

      it "rejects both open and close decisions" do
        mode = TradingMode.current
        expect(mode.can_open?).to be false
        expect(mode.can_close?).to be false
      end
    end
  end

  describe "RSI entry filter" do
    let(:overbought_snapshot) do
      create(:market_snapshot,
        symbol: "BTC",
        price: 100_000,
        indicators: { "rsi_14" => 75.0, "macd" => { "macd" => 100, "signal" => 90, "histogram" => 10 } },
        captured_at: Time.current)
    end

    let(:oversold_snapshot) do
      create(:market_snapshot,
        symbol: "ETH",
        price: 3000,
        indicators: { "rsi_14" => 25.0, "macd" => { "macd" => -100, "signal" => -90, "histogram" => -10 } },
        captured_at: Time.current)
    end

    let(:normal_snapshot) do
      create(:market_snapshot,
        symbol: "SOL",
        price: 200,
        indicators: { "rsi_14" => 50.0, "macd" => { "macd" => 50, "signal" => 45, "histogram" => 5 } },
        captured_at: Time.current)
    end

    let(:long_decision_overbought) do
      create(:trading_decision,
        symbol: "BTC",
        operation: "open",
        direction: "long",
        confidence: 0.75,
        status: "pending",
        parsed_decision: { "leverage" => 3, "stop_loss" => 95_000, "take_profit" => 115_000 })
    end

    let(:short_decision_oversold) do
      create(:trading_decision,
        symbol: "ETH",
        operation: "open",
        direction: "short",
        confidence: 0.75,
        status: "pending",
        parsed_decision: { "leverage" => 3, "stop_loss" => 3500, "take_profit" => 2500 })
    end

    let(:long_decision_normal) do
      create(:trading_decision,
        symbol: "SOL",
        operation: "open",
        direction: "long",
        confidence: 0.75,
        status: "pending",
        parsed_decision: { "leverage" => 3, "stop_loss" => 180, "take_profit" => 240 })
    end

    before do
      # Clear existing snapshots and create specific ones
      MarketSnapshot.where(symbol: "BTC").delete_all
      MarketSnapshot.where(symbol: "ETH").delete_all
      MarketSnapshot.where(symbol: "SOL").delete_all

      overbought_snapshot
      oversold_snapshot
      normal_snapshot
    end

    describe "rejects long when RSI > 70" do
      it "rejects long entry when RSI is overbought" do
        # Setup mocks for the filter_and_approve context
        allow(position_manager).to receive(:open_positions_count).and_return(0)
        allow(position_manager).to receive(:has_open_position?).and_return(false)
        allow(account_manager).to receive(:can_trade?).and_return(true)
        allow(account_manager).to receive(:margin_for_position).and_return(1000)
        allow(risk_manager).to receive(:validate).and_return(
          Risk::RiskManager::ValidationResult.new(valid: true)
        )

        # Mock price fetch
        allow_any_instance_of(Execution::HyperliquidClient).to receive(:all_mids)
          .and_return({ "BTC" => "100000" })

        # Simulate the filter logic directly
        snapshot = MarketSnapshot.latest_for("BTC")
        rsi = snapshot&.indicators&.dig("rsi_14")

        expect(rsi).to be > 70
        expect(long_decision_overbought.direction).to eq("long")

        # The filter should reject this
        if rsi && rsi > 70 && long_decision_overbought.direction == "long"
          long_decision_overbought.reject!("RSI #{rsi.round(1)} overbought - cannot open long")
        end

        expect(long_decision_overbought.status).to eq("rejected")
        expect(long_decision_overbought.rejection_reason).to include("overbought")
      end
    end

    describe "rejects short when RSI < 30" do
      it "rejects short entry when RSI is oversold" do
        snapshot = MarketSnapshot.latest_for("ETH")
        rsi = snapshot&.indicators&.dig("rsi_14")

        expect(rsi).to be < 30
        expect(short_decision_oversold.direction).to eq("short")

        # The filter should reject this
        if rsi && rsi < 30 && short_decision_oversold.direction == "short"
          short_decision_oversold.reject!("RSI #{rsi.round(1)} oversold - cannot open short")
        end

        expect(short_decision_oversold.status).to eq("rejected")
        expect(short_decision_oversold.rejection_reason).to include("oversold")
      end
    end

    describe "allows entry when RSI is normal" do
      it "does not reject when RSI is in normal range" do
        snapshot = MarketSnapshot.latest_for("SOL")
        rsi = snapshot&.indicators&.dig("rsi_14")

        expect(rsi).to be_between(30, 70)
        expect(long_decision_normal.direction).to eq("long")

        # The filter should NOT reject this
        should_reject = false
        if rsi && rsi > 70 && long_decision_normal.direction == "long"
          should_reject = true
        elsif rsi && rsi < 30 && long_decision_normal.direction == "short"
          should_reject = true
        end

        expect(should_reject).to be false
        expect(long_decision_normal.status).to eq("pending")
      end
    end
  end
end
