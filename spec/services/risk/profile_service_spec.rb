# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::ProfileService do
  before do
    # Clean up any existing profiles from previous tests
    RiskProfile.delete_all
  end

  describe ".current_params" do
    it "returns parameters for the current profile" do
      create(:risk_profile, name: "moderate")
      params = described_class.current_params

      expect(params[:rsi_oversold]).to eq(30)
      expect(params[:rsi_overbought]).to eq(70)
      expect(params[:min_confidence]).to eq(0.6)
    end

    it "returns cautious parameters when cautious profile is active" do
      create(:risk_profile, name: "cautious")
      params = described_class.current_params

      expect(params[:rsi_oversold]).to eq(35)
      expect(params[:rsi_overbought]).to eq(65)
      expect(params[:min_confidence]).to eq(0.7)
      expect(params[:max_position_size]).to eq(0.03)
      expect(params[:default_leverage]).to eq(2)
      expect(params[:max_open_positions]).to eq(3)
    end

    it "returns fearless parameters when fearless profile is active" do
      create(:risk_profile, name: "fearless")
      params = described_class.current_params

      expect(params[:rsi_oversold]).to eq(25)
      expect(params[:rsi_overbought]).to eq(75)
      expect(params[:min_confidence]).to eq(0.5)
      expect(params[:max_position_size]).to eq(0.08)
      expect(params[:default_leverage]).to eq(5)
      expect(params[:max_open_positions]).to eq(7)
    end
  end

  describe "parameter accessors" do
    before { create(:risk_profile, name: "moderate") }

    it ".rsi_oversold returns the RSI oversold threshold" do
      expect(described_class.rsi_oversold).to eq(30)
    end

    it ".rsi_overbought returns the RSI overbought threshold" do
      expect(described_class.rsi_overbought).to eq(70)
    end

    it ".rsi_pullback_threshold returns the RSI pullback threshold" do
      expect(described_class.rsi_pullback_threshold).to eq(65)
    end

    it ".rsi_bounce_threshold returns the RSI bounce threshold" do
      expect(described_class.rsi_bounce_threshold).to eq(35)
    end

    it ".min_risk_reward_ratio returns the minimum R/R ratio" do
      expect(described_class.min_risk_reward_ratio).to eq(1.5)
    end

    it ".min_confidence returns the minimum confidence" do
      expect(described_class.min_confidence).to eq(0.6)
    end

    it ".max_position_size returns the maximum position size" do
      expect(described_class.max_position_size).to eq(0.05)
    end

    it ".default_leverage returns the default leverage" do
      expect(described_class.default_leverage).to eq(3)
    end

    it ".max_open_positions returns the maximum open positions" do
      expect(described_class.max_open_positions).to eq(5)
    end
  end

  describe ".current_name" do
    it "returns the name of the current profile" do
      create(:risk_profile, name: "fearless")
      expect(described_class.current_name).to eq("fearless")
    end
  end

  describe ".profile_description" do
    it "returns CAUTIOUS description for cautious profile" do
      create(:risk_profile, name: "cautious")
      description = described_class.profile_description

      expect(description).to include("CAUTIOUS")
      expect(description).to include("Conservative")
    end

    it "returns MODERATE description for moderate profile" do
      create(:risk_profile, name: "moderate")
      description = described_class.profile_description

      expect(description).to include("MODERATE")
      expect(description).to include("Balanced")
    end

    it "returns FEARLESS description for fearless profile" do
      create(:risk_profile, name: "fearless")
      description = described_class.profile_description

      expect(description).to include("FEARLESS")
      expect(description).to include("Aggressive")
    end
  end

  describe "profile switching" do
    it "returns updated parameters after profile switch" do
      create(:risk_profile, name: "moderate")
      expect(described_class.rsi_oversold).to eq(30)

      RiskProfile.switch_to!("cautious")
      expect(described_class.rsi_oversold).to eq(35)

      RiskProfile.switch_to!("fearless")
      expect(described_class.rsi_oversold).to eq(25)
    end
  end
end
