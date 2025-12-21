# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reasoning::DecisionParser do
  describe ".parse_trading_decision" do
    context "with valid JSON" do
      let(:valid_response) do
        {
          operation: "open",
          symbol: "BTC",
          direction: "long",
          leverage: 5,
          target_position: 0.02,
          stop_loss: 95_000,
          take_profit: 105_000,
          confidence: 0.78,
          reasoning: "Strong bullish momentum with RSI neutral"
        }.to_json
      end

      it "returns valid result with parsed data" do
        result = described_class.parse_trading_decision(valid_response)
        expect(result[:valid]).to be true
        expect(result[:data][:operation]).to eq("open")
        expect(result[:data][:symbol]).to eq("BTC")
        expect(result[:data][:direction]).to eq("long")
        expect(result[:data][:confidence]).to eq(0.78)
        expect(result[:errors]).to be_empty
      end
    end

    context "with hold operation" do
      let(:hold_response) do
        {
          operation: "hold",
          symbol: "ETH",
          confidence: 0.5,
          reasoning: "No clear setup at current levels"
        }.to_json
      end

      it "returns valid result for hold operation" do
        result = described_class.parse_trading_decision(hold_response)
        expect(result[:valid]).to be true
        expect(result[:data][:operation]).to eq("hold")
        expect(result[:data][:direction]).to be_nil
      end
    end

    context "with markdown code block wrapper" do
      let(:markdown_response) do
        <<~RESPONSE
          ```json
          {
            "operation": "hold",
            "symbol": "BTC",
            "confidence": 0.5,
            "reasoning": "Market consolidating"
          }
          ```
        RESPONSE
      end

      it "extracts JSON from markdown code block" do
        result = described_class.parse_trading_decision(markdown_response)
        expect(result[:valid]).to be true
        expect(result[:data][:operation]).to eq("hold")
      end
    end

    context "with plain json code block" do
      let(:response) do
        "```\n{\"operation\": \"hold\", \"symbol\": \"BTC\", \"confidence\": 0.5, \"reasoning\": \"test\"}\n```"
      end

      it "extracts JSON from plain code block" do
        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be true
      end
    end

    context "with invalid JSON" do
      let(:invalid_json) { "not valid json {" }

      it "returns invalid result with error" do
        result = described_class.parse_trading_decision(invalid_json)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/parse/i))
      end
    end

    context "with empty response" do
      it "returns invalid result for nil" do
        result = described_class.parse_trading_decision(nil)
        expect(result[:valid]).to be false
        expect(result[:errors]).not_to be_empty
      end

      it "returns invalid result for empty string" do
        result = described_class.parse_trading_decision("")
        expect(result[:valid]).to be false
        expect(result[:errors]).not_to be_empty
      end
    end

    context "with missing required fields" do
      let(:missing_fields) do
        { operation: "open" }.to_json
      end

      it "returns invalid result with validation errors" do
        result = described_class.parse_trading_decision(missing_fields)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/symbol/i))
        expect(result[:errors]).to include(match(/confidence/i))
        expect(result[:errors]).to include(match(/reasoning/i))
      end
    end

    context "with invalid operation" do
      let(:invalid_operation) do
        {
          operation: "invalid",
          symbol: "BTC",
          confidence: 0.5,
          reasoning: "test"
        }.to_json
      end

      it "returns invalid result" do
        result = described_class.parse_trading_decision(invalid_operation)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/operation/i))
      end
    end

    context "with invalid symbol" do
      let(:invalid_symbol) do
        {
          operation: "hold",
          symbol: "INVALID",
          confidence: 0.5,
          reasoning: "test"
        }.to_json
      end

      it "returns invalid result" do
        result = described_class.parse_trading_decision(invalid_symbol)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/symbol/i))
      end
    end

    context "with confidence out of range" do
      it "rejects confidence below 0" do
        response = { operation: "hold", symbol: "BTC", confidence: -0.1, reasoning: "test" }.to_json
        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/confidence/i))
      end

      it "rejects confidence above 1" do
        response = { operation: "hold", symbol: "BTC", confidence: 1.5, reasoning: "test" }.to_json
        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/confidence/i))
      end
    end

    context "with open operation validation rules" do
      it "requires direction for open operation" do
        response = {
          operation: "open",
          symbol: "BTC",
          leverage: 5,
          stop_loss: 95_000,
          confidence: 0.78,
          reasoning: "test"
        }.to_json

        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/direction/i))
      end

      it "requires stop_loss for open operation" do
        response = {
          operation: "open",
          symbol: "BTC",
          direction: "long",
          leverage: 5,
          confidence: 0.78,
          reasoning: "test"
        }.to_json

        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/stop_loss/i))
      end

      it "requires leverage for open operation" do
        response = {
          operation: "open",
          symbol: "BTC",
          direction: "long",
          stop_loss: 95_000,
          confidence: 0.78,
          reasoning: "test"
        }.to_json

        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/leverage/i))
      end
    end

    context "with leverage validation" do
      it "rejects leverage > 10" do
        response = {
          operation: "open",
          symbol: "BTC",
          direction: "long",
          leverage: 15,
          stop_loss: 95_000,
          confidence: 0.78,
          reasoning: "test"
        }.to_json

        result = described_class.parse_trading_decision(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/leverage/i))
      end
    end
  end

  describe ".parse_macro_strategy" do
    context "with valid JSON" do
      let(:valid_response) do
        {
          market_narrative: "Bitcoin showing strength above 50-day EMA with bullish momentum across major assets.",
          bias: "bullish",
          risk_tolerance: 0.7,
          key_levels: {
            "BTC" => { "support" => [ 95_000, 92_000 ], "resistance" => [ 100_000, 105_000 ] },
            "ETH" => { "support" => [ 3200, 3000 ], "resistance" => [ 3500, 3800 ] }
          },
          reasoning: "Strong technical setup across markets with favorable sentiment"
        }.to_json
      end

      it "returns valid result with parsed data" do
        result = described_class.parse_macro_strategy(valid_response)
        expect(result[:valid]).to be true
        expect(result[:data][:bias]).to eq("bullish")
        expect(result[:data][:risk_tolerance]).to eq(0.7)
        expect(result[:data][:key_levels]).to be_a(Hash)
        expect(result[:errors]).to be_empty
      end
    end

    context "with markdown code block" do
      let(:markdown_response) do
        <<~RESPONSE
          ```json
          {
            "market_narrative": "Market consolidating",
            "bias": "neutral",
            "risk_tolerance": 0.5,
            "key_levels": {},
            "reasoning": "Mixed signals"
          }
          ```
        RESPONSE
      end

      it "extracts JSON from markdown code block" do
        result = described_class.parse_macro_strategy(markdown_response)
        expect(result[:valid]).to be true
        expect(result[:data][:bias]).to eq("neutral")
      end
    end

    context "with missing required fields" do
      let(:missing_fields) do
        { bias: "bullish" }.to_json
      end

      it "returns invalid result with validation errors" do
        result = described_class.parse_macro_strategy(missing_fields)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/market_narrative/i))
        expect(result[:errors]).to include(match(/risk_tolerance/i))
      end
    end

    context "with invalid bias" do
      let(:invalid_bias) do
        {
          market_narrative: "Test narrative for macro strategy",
          bias: "invalid",
          risk_tolerance: 0.5,
          key_levels: {},
          reasoning: "test"
        }.to_json
      end

      it "returns invalid result" do
        result = described_class.parse_macro_strategy(invalid_bias)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/bias/i))
      end
    end

    context "with risk_tolerance out of range" do
      it "rejects risk_tolerance below 0" do
        response = {
          market_narrative: "Test narrative for macro strategy",
          bias: "neutral",
          risk_tolerance: -0.1,
          key_levels: {},
          reasoning: "test"
        }.to_json

        result = described_class.parse_macro_strategy(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/risk_tolerance/i))
      end

      it "rejects risk_tolerance above 1" do
        response = {
          market_narrative: "Test narrative for macro strategy",
          bias: "neutral",
          risk_tolerance: 1.5,
          key_levels: {},
          reasoning: "test"
        }.to_json

        result = described_class.parse_macro_strategy(response)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/risk_tolerance/i))
      end
    end

    context "with market_narrative too short" do
      let(:short_narrative) do
        {
          market_narrative: "Short",
          bias: "neutral",
          risk_tolerance: 0.5,
          key_levels: {},
          reasoning: "test"
        }.to_json
      end

      it "returns invalid result" do
        result = described_class.parse_macro_strategy(short_narrative)
        expect(result[:valid]).to be false
        expect(result[:errors]).to include(match(/market_narrative/i))
      end
    end
  end
end
