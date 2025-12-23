# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::OrderExecutor do
  let(:executor) { described_class.new }
  let(:mock_client) { instance_double(Execution::HyperliquidClient) }
  let(:mock_account_manager) { instance_double(Execution::AccountManager) }
  let(:mock_position_manager) { instance_double(Execution::PositionManager) }

  before do
    allow(Execution::HyperliquidClient).to receive(:new).and_return(mock_client)
    allow(Execution::AccountManager).to receive(:new).and_return(mock_account_manager)
    allow(Execution::PositionManager).to receive(:new).and_return(mock_position_manager)
    allow(mock_client).to receive(:configured?).and_return(true)
    allow(mock_client).to receive(:all_mids).and_return({ "BTC" => "100000" })
    # Default stubs for validation
    allow(mock_account_manager).to receive(:margin_for_position).and_return(1000)
    allow(mock_account_manager).to receive(:can_trade?).and_return(true)
    allow(mock_position_manager).to receive(:has_open_position?).and_return(false)
    allow(mock_position_manager).to receive(:open_position).and_return(build(:position))
  end

  describe "#execute" do
    let(:decision) do
      create(:trading_decision,
        symbol: "BTC",
        operation: "open",
        direction: "long",
        confidence: 0.8,
        parsed_decision: {
          "leverage" => 5,
          "target_position" => 0.02,
          "stop_loss" => 95_000,
          "take_profit" => 110_000
        })
    end

    context "in paper trading mode" do
      before do
        allow(Settings.trading).to receive(:paper_trading).and_return(true)
        allow(mock_position_manager).to receive(:has_open_position?).and_return(false)
        allow(mock_account_manager).to receive(:can_trade?).and_return(true)
      end

      it "creates a simulated order" do
        result = executor.execute(decision)

        expect(result).to be_an(Order)
        expect(result.status).to eq("filled")
        expect(result.trading_decision).to eq(decision)
      end

      it "simulates order fill with current market price" do
        result = executor.execute(decision)

        expect(result.average_fill_price).to eq(100_000)
        expect(result.filled_size).to eq(result.size)
      end

      it "creates a simulated position with SL/TP" do
        expect(mock_position_manager).to receive(:open_position).with(
          hash_including(
            symbol: "BTC",
            direction: "long",
            size: 0.02,
            entry_price: 100_000,
            leverage: 5,
            stop_loss_price: 95_000,
            take_profit_price: 110_000
          )
        ).and_return(build(:position))

        executor.execute(decision)
      end

      it "marks decision as executed" do
        executor.execute(decision)

        expect(decision.reload.status).to eq("executed")
      end

      it "logs the paper trade" do
        expect { executor.execute(decision) }
          .to change { ExecutionLog.count }.by(1)

        log = ExecutionLog.last
        expect(log.action).to eq("place_order")
        expect(log.response_payload).to include("paper_trade" => true)
      end
    end

    context "in live trading mode" do
      before do
        allow(Settings.trading).to receive(:paper_trading).and_return(false)
        allow(mock_client).to receive(:place_order)
          .and_raise(Execution::HyperliquidClient::WriteOperationNotImplemented.new("Write operations not implemented"))
      end

      it "raises WriteOperationNotImplemented" do
        expect { executor.execute(decision) }
          .to raise_error(Execution::HyperliquidClient::WriteOperationNotImplemented)
      end

      it "marks decision as failed" do
        executor.execute(decision) rescue nil

        expect(decision.reload.status).to eq("failed")
      end
    end

    context "with validation failures" do
      before do
        allow(Settings.trading).to receive(:paper_trading).and_return(true)
      end

      it "rejects low confidence decisions" do
        decision.update!(confidence: 0.4)

        result = executor.execute(decision)

        expect(result).to be_nil
        expect(decision.reload.status).to eq("rejected")
        expect(decision.rejection_reason.downcase).to include("confidence")
      end

      it "rejects when existing position exists" do
        allow(mock_position_manager).to receive(:has_open_position?).and_return(true)

        result = executor.execute(decision)

        expect(result).to be_nil
        expect(decision.reload.status).to eq("rejected")
      end

      it "rejects when insufficient margin" do
        allow(mock_position_manager).to receive(:has_open_position?).and_return(false)
        allow(mock_account_manager).to receive(:can_trade?).and_return(false)

        result = executor.execute(decision)

        expect(result).to be_nil
        expect(decision.reload.status).to eq("rejected")
        expect(decision.rejection_reason).to include("margin")
      end
    end
  end

  describe "#execute_close" do
    let(:position) { create(:position, symbol: "BTC", direction: "long", status: "open", size: 0.1) }
    let(:decision) do
      create(:trading_decision,
        symbol: "BTC",
        operation: "close",
        confidence: 0.9)
    end

    before do
      allow(Settings.trading).to receive(:paper_trading).and_return(true)
      allow(mock_position_manager).to receive(:get_open_position).and_return(position)
      allow(mock_position_manager).to receive(:close_position)
      allow(mock_position_manager).to receive(:has_open_position?).with("BTC").and_return(true)
    end

    it "creates a sell order to close position" do
      result = executor.execute(decision)

      expect(result.side).to eq("sell")
      expect(result.size).to eq(position.size)
    end

    it "closes the position" do
      expect(mock_position_manager).to receive(:close_position).with(position)

      executor.execute(decision)
    end

    it "marks decision as executed" do
      executor.execute(decision)

      expect(decision.reload.status).to eq("executed")
    end

    context "when no open position exists" do
      before do
        allow(mock_position_manager).to receive(:has_open_position?).with("BTC").and_return(false)
        allow(mock_position_manager).to receive(:get_open_position).and_return(nil)
      end

      it "rejects the decision" do
        result = executor.execute(decision)

        expect(result).to be_nil
        expect(decision.reload.status).to eq("rejected")
        expect(decision.rejection_reason).to include("No open position")
      end
    end
  end

  describe "#build_order_params" do
    let(:decision) do
      build(:trading_decision,
        symbol: "BTC",
        operation: "open",
        direction: "long",
        parsed_decision: {
          "leverage" => 5,
          "target_position" => 0.02
        })
    end

    it "builds correct order parameters" do
      params = executor.send(:build_order_params, decision, 100_000)

      expect(params[:symbol]).to eq("BTC")
      expect(params[:side]).to eq("buy")
      expect(params[:size]).to eq(0.02)
      expect(params[:order_type]).to eq("market")
    end

    it "uses sell side for short positions" do
      decision.direction = "short"

      params = executor.send(:build_order_params, decision, 100_000)

      expect(params[:side]).to eq("sell")
    end

    it "uses sell side for close operations on long positions" do
      decision.operation = "close"
      decision.direction = nil

      # Mock existing long position
      position = build(:position, direction: "long", size: 0.1)
      allow(mock_position_manager).to receive(:get_open_position).and_return(position)

      params = executor.send(:build_order_params, decision, 100_000)

      expect(params[:side]).to eq("sell")
      expect(params[:size]).to eq(0.1)
    end
  end

  describe "#validate_decision" do
    let(:decision) { build(:trading_decision, operation: "open", confidence: 0.8) }

    before do
      allow(mock_position_manager).to receive(:has_open_position?).and_return(false)
      allow(mock_account_manager).to receive(:can_trade?).and_return(true)
    end

    it "returns success for valid decision" do
      result = executor.send(:validate_decision, decision)

      expect(result[:valid]).to be true
    end

    it "fails for hold operations" do
      decision.operation = "hold"

      result = executor.send(:validate_decision, decision)

      expect(result[:valid]).to be false
      expect(result[:reason]).to include("hold")
    end

    it "fails for low confidence" do
      decision.confidence = 0.4

      result = executor.send(:validate_decision, decision)

      expect(result[:valid]).to be false
      expect(result[:reason].downcase).to include("confidence")
    end
  end
end
