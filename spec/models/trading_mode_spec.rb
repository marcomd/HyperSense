# frozen_string_literal: true

require "rails_helper"

RSpec.describe TradingMode do
  describe "validations" do
    it "is valid with valid attributes" do
      trading_mode = build(:trading_mode)
      expect(trading_mode).to be_valid
    end

    it "requires mode" do
      trading_mode = build(:trading_mode, mode: nil)
      expect(trading_mode).not_to be_valid
      expect(trading_mode.errors[:mode]).to include("can't be blank")
    end

    it "requires mode to be one of enabled, exit_only, blocked" do
      %w[enabled exit_only blocked].each do |valid_mode|
        trading_mode = build(:trading_mode, mode: valid_mode)
        expect(trading_mode).to be_valid
      end

      trading_mode = build(:trading_mode, mode: "invalid")
      expect(trading_mode).not_to be_valid
      expect(trading_mode.errors[:mode]).to include("is not included in the list")
    end
  end

  describe ".current" do
    it "returns the first record" do
      trading_mode = create(:trading_mode)
      expect(described_class.current).to eq(trading_mode)
    end

    it "creates a default enabled mode if none exists" do
      expect(described_class.count).to eq(0)
      trading_mode = described_class.current
      expect(trading_mode).to be_persisted
      expect(trading_mode.mode).to eq("enabled")
      expect(described_class.count).to eq(1)
    end

    it "always returns the same record" do
      first_call = described_class.current
      second_call = described_class.current
      expect(first_call.id).to eq(second_call.id)
    end
  end

  describe ".current_mode" do
    it "returns the mode of the current trading mode" do
      create(:trading_mode, :exit_only)
      expect(described_class.current_mode).to eq("exit_only")
    end

    it "returns enabled by default when no mode exists" do
      expect(described_class.current_mode).to eq("enabled")
    end
  end

  describe ".switch_to!" do
    it "switches to the specified mode" do
      create(:trading_mode, mode: "enabled")
      described_class.switch_to!("exit_only", changed_by: "dashboard")

      expect(described_class.current_mode).to eq("exit_only")
      expect(described_class.current.changed_by).to eq("dashboard")
    end

    it "stores the reason when provided" do
      create(:trading_mode, mode: "enabled")
      described_class.switch_to!("exit_only", changed_by: "circuit_breaker", reason: "Daily loss exceeded 5%")

      expect(described_class.current.reason).to eq("Daily loss exceeded 5%")
    end

    it "clears the reason when not provided" do
      create(:trading_mode, mode: "enabled", reason: "old reason")
      described_class.switch_to!("exit_only", changed_by: "dashboard")

      expect(described_class.current.reason).to be_nil
    end

    it "raises ArgumentError for invalid mode name" do
      create(:trading_mode)
      expect { described_class.switch_to!("invalid") }.to raise_error(ArgumentError, /Invalid mode/)
    end

    it "updates the existing record instead of creating new ones" do
      create(:trading_mode, mode: "enabled")
      expect { described_class.switch_to!("exit_only") }.not_to change { described_class.count }
    end
  end

  describe "#can_open?" do
    it "returns true when mode is enabled" do
      trading_mode = build(:trading_mode, mode: "enabled")
      expect(trading_mode.can_open?).to be true
    end

    it "returns false when mode is exit_only" do
      trading_mode = build(:trading_mode, mode: "exit_only")
      expect(trading_mode.can_open?).to be false
    end

    it "returns false when mode is blocked" do
      trading_mode = build(:trading_mode, mode: "blocked")
      expect(trading_mode.can_open?).to be false
    end
  end

  describe "#can_close?" do
    it "returns true when mode is enabled" do
      trading_mode = build(:trading_mode, mode: "enabled")
      expect(trading_mode.can_close?).to be true
    end

    it "returns true when mode is exit_only" do
      trading_mode = build(:trading_mode, mode: "exit_only")
      expect(trading_mode.can_close?).to be true
    end

    it "returns false when mode is blocked" do
      trading_mode = build(:trading_mode, mode: "blocked")
      expect(trading_mode.can_close?).to be false
    end
  end

  describe "MODES constant" do
    it "includes all valid mode names" do
      expect(described_class::MODES).to eq(%w[enabled exit_only blocked])
    end
  end
end
