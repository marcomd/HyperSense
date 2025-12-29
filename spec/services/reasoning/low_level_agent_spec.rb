# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reasoning::LowLevelAgent do
  let(:agent) { described_class.new }
  let(:macro_strategy) { create(:macro_strategy) }

  # Create market data for context assembly
  before do
    create(:market_snapshot, symbol: "BTC", price: 97_000, captured_at: Time.current)
    create(:market_snapshot, symbol: "ETH", price: 3_400, captured_at: Time.current)
    create(:market_snapshot, symbol: "SOL", price: 190, captured_at: Time.current)
    create(:market_snapshot, symbol: "BNB", price: 700, captured_at: Time.current)
  end

  describe "#decide" do
    context "with open decision response" do
      let(:open_decision_response) do
        {
          operation: "open",
          symbol: "BTC",
          direction: "long",
          leverage: 5,
          target_position: 0.02,
          stop_loss: 95_000,
          take_profit: 105_000,
          confidence: 0.78,
          reasoning: "RSI neutral at 62, MACD bullish crossover, price above all EMAs"
        }.to_json
      end

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(open_decision_response)
      end

      it "creates a TradingDecision record" do
        expect { agent.decide(symbol: "BTC", macro_strategy: macro_strategy) }
          .to change(TradingDecision, :count).by(1)
      end

      it "returns the created decision" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision).to be_a(TradingDecision)
        expect(decision).to be_persisted
      end

      it "sets the correct operation" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.operation).to eq("open")
      end

      it "sets the direction" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.direction).to eq("long")
      end

      it "sets the confidence" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.confidence).to eq(0.78)
      end

      it "stores the parsed decision" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.parsed_decision["leverage"]).to eq(5)
        expect(decision.parsed_decision["operation"]).to eq("open")
        expect(decision.parsed_decision["direction"]).to eq("long")
      end

      it "associates with macro_strategy" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.macro_strategy).to eq(macro_strategy)
      end

      it "stores the context sent" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.context_sent).to include("timestamp", "symbol")
      end

      it "stores the LLM response" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.llm_response).to include("raw", "parsed")
      end

      it "sets status to pending" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.status).to eq("pending")
      end

      it "stores the llm_model" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.llm_model).to be_present
        expect(decision.llm_model).to eq(Settings.llm.send(Settings.llm.provider).model)
      end
    end

    context "with hold decision response" do
      let(:hold_decision_response) do
        {
          operation: "hold",
          symbol: "ETH",
          confidence: 0.55,
          reasoning: "No clear setup at current levels, RSI neutral, waiting for better entry"
        }.to_json
      end

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(hold_decision_response)
      end

      it "creates a hold decision" do
        decision = agent.decide(symbol: "ETH", macro_strategy: macro_strategy)
        expect(decision.operation).to eq("hold")
        expect(decision.direction).to be_nil
      end

      it "is not actionable" do
        decision = agent.decide(symbol: "ETH", macro_strategy: macro_strategy)
        expect(decision.actionable?).to be false
        expect(decision.hold?).to be true
      end
    end

    context "with invalid LLM response" do
      let(:invalid_response) { "{ invalid json" }

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(invalid_response)
      end

      it "creates a rejected hold decision" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.operation).to eq("hold")
        expect(decision.status).to eq("rejected")
      end

      it "includes rejection reason" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.rejection_reason).to include("Invalid LLM response")
      end

      it "sets confidence to 0" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.confidence).to eq(0.0)
      end

      it "stores the llm_model even on invalid response" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.llm_model).to be_present
      end
    end

    context "without macro_strategy" do
      let(:hold_response) do
        {
          operation: "hold",
          symbol: "BTC",
          confidence: 0.5,
          reasoning: "No macro context available"
        }.to_json
      end

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(hold_response)
      end

      it "works without macro strategy" do
        decision = agent.decide(symbol: "BTC", macro_strategy: nil)
        expect(decision).to be_a(TradingDecision)
        expect(decision.macro_strategy).to be_nil
      end
    end

    context "with API error" do
      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_raise(
          LLM::APIError.new("Connection failed")
        )
      end

      it "creates an error hold decision" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.operation).to eq("hold")
        expect(decision.status).to eq("rejected")
      end

      it "includes error in rejection reason" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.rejection_reason).to include("Connection failed")
      end

      it "stores the llm_model even on API error" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.llm_model).to be_present
      end
    end

    context "with close decision response" do
      let!(:open_position) do
        create(:position,
          symbol: "BTC",
          direction: "long",
          size: 0.05,
          entry_price: 95_000,
          current_price: 100_000,
          unrealized_pnl: 250,
          leverage: 5)
      end

      let(:close_decision_response) do
        {
          operation: "close",
          symbol: "BTC",
          confidence: 0.85,
          reasoning: "Take profit target reached, securing gains"
        }.to_json
      end

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(close_decision_response)
      end

      it "creates a close decision" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.operation).to eq("close")
      end

      it "sets the confidence" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.confidence).to eq(0.85)
      end

      it "is actionable" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.actionable?).to be true
      end

      it "stores the context with position data" do
        decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
        expect(decision.context_sent["current_position"]["has_position"]).to be true
        expect(decision.context_sent["current_position"]["direction"]).to eq("long")
      end
    end

    context "position awareness in context" do
      let(:hold_response) do
        {
          operation: "hold",
          symbol: "BTC",
          confidence: 0.5,
          reasoning: "No clear setup"
        }.to_json
      end

      before do
        allow_any_instance_of(LLM::Client).to receive(:chat).and_return(hold_response)
      end

      context "without open position" do
        it "includes current_position in context_sent" do
          decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
          expect(decision.context_sent).to include("current_position")
        end

        it "has has_position: false when no position exists" do
          decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
          expect(decision.context_sent["current_position"]["has_position"]).to be false
        end
      end

      context "with open position" do
        let!(:open_position) do
          create(:position,
            symbol: "BTC",
            direction: "short",
            size: 0.03,
            entry_price: 100_000,
            current_price: 97_000,
            unrealized_pnl: 90,
            leverage: 3)
        end

        it "has has_position: true when position exists" do
          decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
          expect(decision.context_sent["current_position"]["has_position"]).to be true
        end

        it "includes position details in context" do
          decision = agent.decide(symbol: "BTC", macro_strategy: macro_strategy)
          position_data = decision.context_sent["current_position"]
          expect(position_data["direction"]).to eq("short")
          expect(position_data["size"]).to eq(0.03)
          expect(position_data["entry_price"]).to eq(100_000.0)
          expect(position_data["leverage"]).to eq(3)
        end
      end
    end
  end

  describe "#decide_all" do
    let(:hold_response) do
      {
        operation: "hold",
        symbol: "BTC",  # Will be replaced dynamically by the agent context
        confidence: 0.5,
        reasoning: "No clear setup"
      }.to_json
    end

    before do
      allow_any_instance_of(LLM::Client).to receive(:chat).and_return(hold_response)
    end

    it "returns decisions for all configured assets" do
      decisions = agent.decide_all(macro_strategy: macro_strategy)
      expect(decisions).to be_an(Array)
      expect(decisions.length).to eq(Settings.assets.to_a.length)
    end

    it "creates TradingDecision for each asset" do
      expect { agent.decide_all(macro_strategy: macro_strategy) }
        .to change(TradingDecision, :count).by(Settings.assets.to_a.length)
    end

    it "includes all configured symbols" do
      decisions = agent.decide_all(macro_strategy: macro_strategy)
      symbols = decisions.map(&:symbol)
      expect(symbols).to include("BTC", "ETH", "SOL", "BNB")
    end
  end

  describe "LLM configuration" do
    it "reads max tokens from settings" do
      expect(described_class.max_tokens).to eq(Settings.llm.low_level.max_tokens)
      expect(described_class.max_tokens).to be > 0
    end

    it "reads temperature from settings" do
      expect(described_class.temperature).to eq(Settings.llm.low_level.temperature)
      expect(described_class.temperature).to be_between(0, 1)
    end
  end
end
