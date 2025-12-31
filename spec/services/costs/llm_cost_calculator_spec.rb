# frozen_string_literal: true

require "rails_helper"

RSpec.describe Costs::LLMCostCalculator do
  subject(:calculator) { described_class.new }

  describe "#estimated_costs" do
    context "with no LLM calls" do
      it "returns zero costs" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:total]).to eq(0.0)
        expect(result[:total_calls]).to eq(0)
      end

      it "includes provider and model info" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:provider]).to eq(Settings.llm.provider.to_s)
        expect(result[:model]).to be_present
      end
    end

    context "with macro strategy calls" do
      before do
        create(:macro_strategy, created_at: 1.day.ago)
        create(:macro_strategy, created_at: 2.days.ago)
      end

      it "counts macro strategy calls" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:macro_strategy][:calls]).to eq(2)
      end

      it "estimates tokens based on max_tokens setting" do
        result = calculator.estimated_costs(since: nil)

        # High-level agent uses 2000 max tokens
        # Estimated output = 2000 * 0.7 (utilization) = 1400
        # Estimated input = 1400 * 3 (ratio) = 4200
        expect(result[:macro_strategy][:estimated_output_tokens]).to eq(1400 * 2)
        expect(result[:macro_strategy][:estimated_input_tokens]).to eq(4200 * 2)
      end

      it "filters by since date" do
        result = calculator.estimated_costs(since: 1.day.ago.beginning_of_day)

        expect(result[:macro_strategy][:calls]).to eq(1)
      end
    end

    context "with trading decision calls" do
      before do
        macro = create(:macro_strategy)
        create(:trading_decision, macro_strategy: macro, created_at: 1.day.ago)
        create(:trading_decision, macro_strategy: macro, created_at: 1.day.ago)
        create(:trading_decision, macro_strategy: macro, created_at: 3.days.ago)
      end

      it "counts trading decision calls" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:trading_decisions][:calls]).to eq(3)
      end

      it "estimates tokens for trading decisions" do
        result = calculator.estimated_costs(since: nil)

        # Low-level agent uses 1500 max tokens
        # Estimated output = 1500 * 0.7 = 1050 per call
        # Estimated input = 1050 * 3 = 3150 per call
        expect(result[:trading_decisions][:estimated_output_tokens]).to eq(1050 * 3)
        expect(result[:trading_decisions][:estimated_input_tokens]).to eq(3150 * 3)
      end
    end

    context "with cost calculation" do
      before do
        macro = create(:macro_strategy)
        create(:trading_decision, macro_strategy: macro)
      end

      it "calculates costs using pricing from settings" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:macro_strategy][:cost]).to be_a(Float)
        expect(result[:trading_decisions][:cost]).to be_a(Float)
        expect(result[:total]).to be >= 0
      end

      it "returns pricing information" do
        result = calculator.estimated_costs(since: nil)

        expect(result[:pricing]).to include(:input_per_million, :output_per_million)
      end
    end
  end

  describe "#current_pricing" do
    it "returns current provider and model" do
      result = calculator.current_pricing

      expect(result[:provider]).to eq(Settings.llm.provider.to_s)
      expect(result[:model]).to be_present
    end

    it "returns pricing rates" do
      result = calculator.current_pricing

      expect(result[:pricing][:input_per_million]).to be_a(Numeric)
      expect(result[:pricing][:output_per_million]).to be_a(Numeric)
    end
  end

  describe "with different providers" do
    context "when using ollama (free)" do
      before do
        allow(Settings.llm).to receive(:provider).and_return("ollama")
        allow(Settings.llm.ollama).to receive(:model).and_return("llama3")
      end

      it "returns zero costs for ollama" do
        # Ollama pricing should be 0
        result = calculator.current_pricing

        expect(result[:pricing][:input_per_million]).to eq(0.0)
        expect(result[:pricing][:output_per_million]).to eq(0.0)
      end
    end
  end
end
