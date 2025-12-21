# frozen_string_literal: true

require "rails_helper"

RSpec.describe MacroStrategy do
  describe "validations" do
    it "is valid with valid attributes" do
      strategy = build(:macro_strategy)
      expect(strategy).to be_valid
    end

    it "requires market_narrative" do
      strategy = build(:macro_strategy, market_narrative: nil)
      expect(strategy).not_to be_valid
      expect(strategy.errors[:market_narrative]).to include("can't be blank")
    end

    it "requires bias" do
      strategy = build(:macro_strategy, bias: nil)
      expect(strategy).not_to be_valid
      expect(strategy.errors[:bias]).to include("can't be blank")
    end

    it "requires bias to be one of bullish, bearish, neutral" do
      %w[bullish bearish neutral].each do |valid_bias|
        strategy = build(:macro_strategy, bias: valid_bias)
        expect(strategy).to be_valid
      end

      strategy = build(:macro_strategy, bias: "invalid")
      expect(strategy).not_to be_valid
      expect(strategy.errors[:bias]).to include("is not included in the list")
    end

    it "requires risk_tolerance" do
      strategy = build(:macro_strategy, risk_tolerance: nil)
      expect(strategy).not_to be_valid
      expect(strategy.errors[:risk_tolerance]).to include("can't be blank")
    end

    it "requires risk_tolerance between 0 and 1" do
      strategy = build(:macro_strategy, risk_tolerance: -0.1)
      expect(strategy).not_to be_valid

      strategy = build(:macro_strategy, risk_tolerance: 1.1)
      expect(strategy).not_to be_valid

      strategy = build(:macro_strategy, risk_tolerance: 0.5)
      expect(strategy).to be_valid
    end

    it "requires valid_until" do
      strategy = build(:macro_strategy, valid_until: nil)
      expect(strategy).not_to be_valid
      expect(strategy.errors[:valid_until]).to include("can't be blank")
    end
  end

  describe "scopes" do
    describe ".current" do
      it "returns only valid (non-stale) strategies" do
        valid_strategy = create(:macro_strategy, valid_until: 1.hour.from_now)
        _stale_strategy = create(:macro_strategy, :stale)

        expect(MacroStrategy.current).to include(valid_strategy)
        expect(MacroStrategy.current.count).to eq(1)
      end

      it "orders by created_at descending" do
        older = create(:macro_strategy, valid_until: 1.hour.from_now, created_at: 2.hours.ago)
        newer = create(:macro_strategy, valid_until: 1.hour.from_now, created_at: 1.hour.ago)

        expect(MacroStrategy.current.first).to eq(newer)
        expect(MacroStrategy.current.last).to eq(older)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        older = create(:macro_strategy, created_at: 2.hours.ago)
        newer = create(:macro_strategy, created_at: 1.hour.ago)

        expect(MacroStrategy.recent.first).to eq(newer)
        expect(MacroStrategy.recent.last).to eq(older)
      end
    end
  end

  describe ".active" do
    it "returns the most recent valid strategy" do
      _stale = create(:macro_strategy, :stale)
      valid = create(:macro_strategy, valid_until: 1.hour.from_now)

      expect(MacroStrategy.active).to eq(valid)
    end

    it "returns nil when no valid strategies exist" do
      create(:macro_strategy, :stale)

      expect(MacroStrategy.active).to be_nil
    end
  end

  describe ".needs_refresh?" do
    it "returns true when no strategies exist" do
      expect(MacroStrategy.needs_refresh?).to be true
    end

    it "returns true when active strategy is stale" do
      create(:macro_strategy, :stale)

      expect(MacroStrategy.needs_refresh?).to be true
    end

    it "returns false when valid strategy exists" do
      create(:macro_strategy, valid_until: 1.hour.from_now)

      expect(MacroStrategy.needs_refresh?).to be false
    end
  end

  describe "#stale?" do
    it "returns true when valid_until is in the past" do
      strategy = build(:macro_strategy, valid_until: 1.hour.ago)
      expect(strategy.stale?).to be true
    end

    it "returns false when valid_until is in the future" do
      strategy = build(:macro_strategy, valid_until: 1.hour.from_now)
      expect(strategy.stale?).to be false
    end
  end

  describe "#support_for" do
    it "returns support levels for a symbol" do
      strategy = build(:macro_strategy, key_levels: {
        "BTC" => { "support" => [ 95_000, 92_000 ], "resistance" => [ 100_000 ] }
      })

      expect(strategy.support_for("BTC")).to eq([ 95_000, 92_000 ])
      expect(strategy.support_for(:BTC)).to eq([ 95_000, 92_000 ])
    end

    it "returns nil for unknown symbol" do
      strategy = build(:macro_strategy, key_levels: {})
      expect(strategy.support_for("UNKNOWN")).to be_nil
    end
  end

  describe "#resistance_for" do
    it "returns resistance levels for a symbol" do
      strategy = build(:macro_strategy, key_levels: {
        "BTC" => { "support" => [ 95_000 ], "resistance" => [ 100_000, 105_000 ] }
      })

      expect(strategy.resistance_for("BTC")).to eq([ 100_000, 105_000 ])
      expect(strategy.resistance_for(:BTC)).to eq([ 100_000, 105_000 ])
    end

    it "returns nil for unknown symbol" do
      strategy = build(:macro_strategy, key_levels: {})
      expect(strategy.resistance_for("UNKNOWN")).to be_nil
    end
  end

  describe "#position_multiplier" do
    it "returns the risk_tolerance value" do
      strategy = build(:macro_strategy, risk_tolerance: 0.7)
      expect(strategy.position_multiplier).to eq(0.7)
    end
  end
end
