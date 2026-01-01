# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reasoning::ContextAssembler do
  # Create market snapshot factory if not exists
  let!(:btc_snapshot) do
    create(:market_snapshot,
      symbol: "BTC",
      price: 97_000,
      high_24h: 98_500,
      low_24h: 95_000,
      volume_24h: 50_000_000,
      price_change_pct_24h: 2.5,
      indicators: {
        "ema_20" => 96_500,
        "ema_50" => 95_000,
        "ema_100" => 92_000,
        "rsi_14" => 62.5,
        "atr_14" => 1_455.0,
        "macd" => { "macd" => 250.0, "signal" => 200.0, "histogram" => 50.0 },
        "pivot_points" => { "pp" => 96_833, "r1" => 98_166, "r2" => 99_333, "s1" => 95_666, "s2" => 94_333 }
      },
      sentiment: {
        "fear_greed" => { "value" => 65, "classification" => "Greed" },
        "fetched_at" => Time.current.iso8601
      },
      captured_at: Time.current)
  end

  let!(:eth_snapshot) do
    create(:market_snapshot,
      symbol: "ETH",
      price: 3_400,
      high_24h: 3_500,
      low_24h: 3_300,
      volume_24h: 25_000_000,
      price_change_pct_24h: 1.5,
      indicators: {
        "ema_20" => 3_350,
        "ema_50" => 3_200,
        "ema_100" => 3_000,
        "rsi_14" => 58.0,
        "atr_14" => 51.0,
        "macd" => { "macd" => 25.0, "signal" => 20.0, "histogram" => 5.0 },
        "pivot_points" => { "pp" => 3_400, "r1" => 3_500, "r2" => 3_600, "s1" => 3_300, "s2" => 3_200 }
      },
      sentiment: {
        "fear_greed" => { "value" => 65, "classification" => "Greed" },
        "fetched_at" => Time.current.iso8601
      },
      captured_at: Time.current)
  end

  let(:macro_strategy) { create(:macro_strategy) }

  describe "#for_trading" do
    context "with a symbol" do
      subject(:assembler) { described_class.new(symbol: "BTC") }

      it "returns a hash with required keys" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context).to include(
          :timestamp,
          :symbol,
          :market_data,
          :technical_indicators,
          :sentiment,
          :macro_context,
          :recent_price_action,
          :risk_parameters
        )
      end

      it "includes market data for the symbol" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:market_data][:price]).to eq(97_000.0)
        expect(context[:market_data][:high_24h]).to eq(98_500.0)
        expect(context[:market_data][:low_24h]).to eq(95_000.0)
        expect(context[:market_data][:volume_24h]).to eq(50_000_000.0)
      end

      it "includes technical indicators" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:technical_indicators][:ema_20]).to eq(96_500)
        expect(context[:technical_indicators][:rsi_14]).to eq(62.5)
        expect(context[:technical_indicators][:atr_14]).to eq(1_455.0)
        expect(context[:technical_indicators][:macd]).to include("macd" => 250.0)
        expect(context[:technical_indicators][:signals]).to include(:rsi, :macd, :atr)
      end

      it "includes ATR volatility signal" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        # BTC: ATR 1455 / price 97000 = 1.5% -> :normal_volatility
        expect(context[:technical_indicators][:signals][:atr]).to eq(:normal_volatility)
      end

      it "includes sentiment data" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:sentiment][:fear_greed_value]).to eq(65)
        expect(context[:sentiment][:fear_greed_classification]).to eq("Greed")
      end

      it "includes macro context when strategy is provided" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:macro_context][:available]).to be true
        expect(context[:macro_context][:bias]).to eq("bullish")
        expect(context[:macro_context][:risk_tolerance]).to be_a(Float)
      end

      it "marks macro context as unavailable when nil" do
        context = assembler.for_trading(macro_strategy: nil)

        expect(context[:macro_context][:available]).to be false
      end

      it "marks macro context as unavailable when stale" do
        stale_strategy = create(:macro_strategy, :stale)
        context = assembler.for_trading(macro_strategy: stale_strategy)

        expect(context[:macro_context][:available]).to be false
      end

      it "includes risk parameters from settings" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:risk_parameters][:max_position_size]).to eq(Settings.risk.max_position_size)
        expect(context[:risk_parameters][:max_leverage]).to eq(Settings.risk.max_leverage)
        expect(context[:risk_parameters][:min_confidence]).to eq(Settings.risk.min_confidence)
      end
    end

    context "without market data" do
      subject(:assembler) { described_class.new(symbol: "UNKNOWN") }

      it "returns empty market data" do
        context = assembler.for_trading(macro_strategy: nil)

        expect(context[:market_data]).to eq({})
        expect(context[:technical_indicators]).to eq({})
      end
    end
  end

  describe "#for_macro_analysis" do
    subject(:assembler) { described_class.new }

    it "returns a hash with required keys" do
      context = assembler.for_macro_analysis

      expect(context).to include(
        :timestamp,
        :assets_overview,
        :market_sentiment,
        :historical_trends,
        :risk_parameters
      )
    end

    it "includes overview of all configured assets" do
      context = assembler.for_macro_analysis

      expect(context[:assets_overview]).to be_an(Array)
      expect(context[:assets_overview].map { |a| a[:symbol] }).to include("BTC", "ETH")
    end

    it "includes asset data for each asset" do
      context = assembler.for_macro_analysis

      btc_overview = context[:assets_overview].find { |a| a[:symbol] == "BTC" }
      expect(btc_overview[:market_data][:price]).to eq(97_000.0)
      expect(btc_overview[:technical_indicators][:rsi_14]).to eq(62.5)
      expect(btc_overview[:technical_indicators][:atr_14]).to eq(1_455.0)
      expect(btc_overview[:technical_indicators][:signals][:atr]).to eq(:normal_volatility)
    end

    it "includes market sentiment" do
      context = assembler.for_macro_analysis

      expect(context[:market_sentiment][:fear_greed_value]).to eq(65)
    end

    it "includes historical trends" do
      context = assembler.for_macro_analysis

      expect(context[:historical_trends]).to be_a(Hash)
      expect(context[:historical_trends].keys).to include("BTC", "ETH")
    end

    it "includes risk parameters" do
      context = assembler.for_macro_analysis

      expect(context[:risk_parameters][:max_position_size]).to eq(Settings.risk.max_position_size)
    end
  end

  describe "trend calculation" do
    subject(:assembler) { described_class.new(symbol: "BTC") }

    before do
      # Create historical price data with an uptrend
      (1..10).each do |i|
        create(:market_snapshot,
          symbol: "BTC",
          price: 95_000 + (i * 200),  # Rising prices
          captured_at: i.hours.ago)
      end
    end

    it "calculates trend from recent price action" do
      context = assembler.for_trading(macro_strategy: nil)

      expect(context[:recent_price_action][:trend]).to be_present
      expect(%w[strong_uptrend uptrend neutral downtrend strong_downtrend]).to include(
        context[:recent_price_action][:trend]
      )
    end
  end

  describe "position awareness" do
    subject(:assembler) { described_class.new(symbol: "BTC") }

    context "when no open position exists" do
      it "includes current_position in context" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context).to include(:current_position)
      end

      it "returns has_position: false" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:has_position]).to be false
      end
    end

    context "when an open position exists" do
      let!(:open_position) do
        create(:position,
          symbol: "BTC",
          direction: "long",
          size: 0.05,
          entry_price: 95_000,
          current_price: 97_000,
          unrealized_pnl: 100,
          leverage: 5,
          stop_loss_price: 93_000,
          take_profit_price: 100_000,
          opened_at: 1.hour.ago)
      end

      it "returns has_position: true" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:has_position]).to be true
      end

      it "includes direction" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:direction]).to eq("long")
      end

      it "includes size" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:size]).to eq(0.05)
      end

      it "includes entry and current price" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:entry_price]).to eq(95_000.0)
        expect(context[:current_position][:current_price]).to eq(97_000.0)
      end

      it "includes unrealized PnL" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:unrealized_pnl]).to eq(100.0)
      end

      it "includes leverage" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:leverage]).to eq(5)
      end

      it "includes stop loss and take profit prices" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:stop_loss_price]).to eq(93_000.0)
        expect(context[:current_position][:take_profit_price]).to eq(100_000.0)
      end

      it "includes opened_at timestamp" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:opened_at]).to be_present
      end
    end

    context "when a closed position exists but no open position" do
      let!(:closed_position) { create(:position, :closed, symbol: "BTC") }

      it "returns has_position: false" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:has_position]).to be false
      end
    end

    context "when position exists for different symbol" do
      let!(:eth_position) { create(:position, :eth, symbol: "ETH") }

      it "returns has_position: false for BTC" do
        context = assembler.for_trading(macro_strategy: macro_strategy)

        expect(context[:current_position][:has_position]).to be false
      end
    end
  end
end
