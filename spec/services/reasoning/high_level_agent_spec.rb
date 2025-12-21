# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reasoning::HighLevelAgent do
  let(:agent) { described_class.new }

  # Create market data for context assembly
  before do
    create(:market_snapshot, symbol: "BTC", price: 97_000, captured_at: Time.current)
    create(:market_snapshot, symbol: "ETH", price: 3_400, captured_at: Time.current)
    create(:market_snapshot, symbol: "SOL", price: 190, captured_at: Time.current)
    create(:market_snapshot, symbol: "BNB", price: 700, captured_at: Time.current)
  end

  describe "#analyze" do
    context "with successful LLM response" do
      let(:valid_llm_response) do
        {
          market_narrative: "Bitcoin showing strength above 50-day EMA with bullish momentum across major assets.",
          bias: "bullish",
          risk_tolerance: 0.7,
          key_levels: {
            "BTC" => { "support" => [ 95_000, 92_000 ], "resistance" => [ 100_000, 105_000 ] },
            "ETH" => { "support" => [ 3200, 3000 ], "resistance" => [ 3500, 3800 ] },
            "SOL" => { "support" => [ 180, 170 ], "resistance" => [ 200, 220 ] },
            "BNB" => { "support" => [ 650, 620 ], "resistance" => [ 700, 750 ] }
          },
          reasoning: "Strong technical setup across markets with RSI neutral and MACD bullish"
        }.to_json
      end

      before do
        # Mock the Anthropic API response
        allow_any_instance_of(Anthropic::Client).to receive_message_chain(:messages, :create).and_return(
          OpenStruct.new(
            content: [ OpenStruct.new(text: valid_llm_response) ]
          )
        )
      end

      it "creates a MacroStrategy record" do
        expect { agent.analyze }.to change(MacroStrategy, :count).by(1)
      end

      it "returns the created strategy" do
        strategy = agent.analyze
        expect(strategy).to be_a(MacroStrategy)
        expect(strategy).to be_persisted
      end

      it "sets the correct bias" do
        strategy = agent.analyze
        expect(strategy.bias).to eq("bullish")
      end

      it "sets the risk tolerance" do
        strategy = agent.analyze
        expect(strategy.risk_tolerance).to eq(0.7)
      end

      it "stores key levels" do
        strategy = agent.analyze
        expect(strategy.key_levels).to be_a(Hash)
        expect(strategy.key_levels["BTC"]).to include("support", "resistance")
      end

      it "sets valid_until based on settings" do
        strategy = agent.analyze
        expected_valid_until = Time.current + Settings.macro.refresh_interval_hours.hours
        expect(strategy.valid_until).to be_within(1.minute).of(expected_valid_until)
      end

      it "stores the context used" do
        strategy = agent.analyze
        expect(strategy.context_used).to be_a(Hash)
        expect(strategy.context_used).to include("timestamp")
      end

      it "stores the LLM response" do
        strategy = agent.analyze
        expect(strategy.llm_response).to be_a(Hash)
        expect(strategy.llm_response).to include("raw", "parsed")
      end
    end

    context "with invalid LLM response" do
      let(:invalid_llm_response) { "{ invalid json" }

      before do
        allow_any_instance_of(Anthropic::Client).to receive_message_chain(:messages, :create).and_return(
          OpenStruct.new(
            content: [ OpenStruct.new(text: invalid_llm_response) ]
          )
        )
      end

      it "creates a fallback neutral strategy" do
        strategy = agent.analyze
        expect(strategy).to be_a(MacroStrategy)
        expect(strategy.bias).to eq("neutral")
      end

      it "sets shorter validity for fallback" do
        strategy = agent.analyze
        # Fallback validity is 6 hours
        expect(strategy.valid_until).to be_within(1.minute).of(Time.current + 6.hours)
      end

      it "includes error info in llm_response" do
        strategy = agent.analyze
        expect(strategy.llm_response).to include("errors")
      end
    end

    context "with API connection error" do
      before do
        allow_any_instance_of(Anthropic::Client).to receive_message_chain(:messages, :create).and_raise(
          Faraday::ConnectionFailed.new("Connection failed")
        )
      end

      it "returns nil" do
        expect(agent.analyze).to be_nil
      end

      it "logs an error" do
        expect(Rails.logger).to receive(:error).with(/API error/)
        agent.analyze
      end
    end

    context "with empty LLM response" do
      before do
        allow_any_instance_of(Anthropic::Client).to receive_message_chain(:messages, :create).and_return(
          OpenStruct.new(content: [ OpenStruct.new(text: nil) ])
        )
      end

      it "raises an error for empty response" do
        # Empty responses should trigger the standard error handling and raise
        expect { agent.analyze }.to raise_error(RuntimeError, /Empty response/)
      end
    end
  end

  describe "LLM configuration" do
    it "reads model from settings" do
      expect(described_class.model).to eq(Settings.llm.model)
    end

    it "reads max tokens from settings" do
      expect(described_class.max_tokens).to eq(Settings.llm.high_level.max_tokens)
      expect(described_class.max_tokens).to be > 0
    end

    it "reads temperature from settings" do
      expect(described_class.temperature).to eq(Settings.llm.high_level.temperature)
      expect(described_class.temperature).to be_between(0, 1)
    end
  end
end
