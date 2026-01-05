# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::ReadinessChecker do
  let(:checker) { described_class.new }

  describe "#check" do
    context "when all data is available" do
      before do
        # Create valid macro strategy
        create(:macro_strategy, :active)

        # Create recent forecasts for at least one asset
        create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)

        # Create fresh market snapshots for all assets
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
        end
      end

      it "returns ready status" do
        result = checker.check
        expect(result.ready?).to be true
        expect(result.missing).to be_empty
      end
    end

    context "when macro strategy is missing" do
      before do
        # Create forecasts and market data but no macro strategy
        create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
        end
      end

      it "returns not ready with valid_macro_strategy missing" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("valid_macro_strategy")
      end
    end

    context "when macro strategy is fallback from parse error" do
      before do
        # Create fallback macro strategy (parse error)
        create(:macro_strategy, :fallback)

        # Create other required data
        create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
        end
      end

      it "returns not ready" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("valid_macro_strategy")
      end
    end

    context "when forecasts are missing" do
      before do
        create(:macro_strategy, :active)
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
        end
        # No forecasts created
      end

      it "returns not ready with forecasts missing" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("forecasts")
      end
    end

    context "when forecasts are stale" do
      before do
        create(:macro_strategy, :active)
        # Create old forecasts (older than 1 hour)
        create(:forecast, symbol: "BTC", created_at: 2.hours.ago)
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
        end
      end

      it "returns not ready" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("forecasts")
      end
    end

    context "when market data is stale" do
      before do
        create(:macro_strategy, :active)
        create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)
        # Create stale market snapshots (older than 5 minutes)
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 10.minutes.ago)
        end
      end

      it "returns not ready with fresh_market_data missing" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("fresh_market_data")
      end
    end

    context "when sentiment data is missing" do
      before do
        create(:macro_strategy, :active)
        create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)
        # Create market snapshots without sentiment
        Settings.assets.to_a.each do |symbol|
          create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago, sentiment: nil)
        end
      end

      it "returns not ready with sentiment_data missing" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("sentiment_data")
      end
    end

    context "when multiple data sources are missing" do
      it "lists all missing items" do
        result = checker.check
        expect(result.ready?).to be false
        expect(result.missing).to include("valid_macro_strategy")
        expect(result.missing).to include("forecasts")
        expect(result.missing).to include("fresh_market_data")
      end
    end
  end

  describe "#status" do
    before do
      create(:macro_strategy, :active)
      create(:forecast, symbol: "BTC", created_at: 30.minutes.ago)
      Settings.assets.to_a.each do |symbol|
        create(:market_snapshot, symbol: symbol, created_at: 2.minutes.ago)
      end
    end

    it "returns detailed status of each check" do
      status = checker.status

      expect(status).to include(
        valid_macro_strategy: true,
        forecasts_available: true,
        fresh_market_data: true,
        sentiment_available: true,
        ready: true
      )
    end
  end

  describe "ReadinessResult" do
    describe "#ready?" do
      it "returns true when ready is true" do
        result = Risk::ReadinessChecker::ReadinessResult.new(ready: true, missing: [])
        expect(result.ready?).to be true
      end

      it "returns false when ready is false" do
        result = Risk::ReadinessChecker::ReadinessResult.new(ready: false, missing: [ "forecasts" ])
        expect(result.ready?).to be false
      end
    end

    describe "#reason" do
      it "returns comma-separated list of missing items" do
        result = Risk::ReadinessChecker::ReadinessResult.new(
          ready: false,
          missing: [ "forecasts", "sentiment_data" ]
        )
        expect(result.reason).to eq("forecasts, sentiment_data")
      end

      it "returns empty string when no missing items" do
        result = Risk::ReadinessChecker::ReadinessResult.new(ready: true, missing: [])
        expect(result.reason).to eq("")
      end
    end
  end
end
