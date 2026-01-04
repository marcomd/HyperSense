# frozen_string_literal: true

require "rails_helper"

RSpec.describe RiskProfile do
  describe "validations" do
    it "is valid with valid attributes" do
      profile = build(:risk_profile)
      expect(profile).to be_valid
    end

    it "requires name" do
      profile = build(:risk_profile, name: nil)
      expect(profile).not_to be_valid
      expect(profile.errors[:name]).to include("can't be blank")
    end

    it "requires name to be one of cautious, moderate, fearless" do
      %w[cautious moderate fearless].each do |valid_name|
        profile = build(:risk_profile, name: valid_name)
        expect(profile).to be_valid
      end

      profile = build(:risk_profile, name: "invalid")
      expect(profile).not_to be_valid
      expect(profile.errors[:name]).to include("is not included in the list")
    end
  end

  describe ".current" do
    it "returns the first record" do
      profile = create(:risk_profile)
      expect(RiskProfile.current).to eq(profile)
    end

    it "creates a default moderate profile if none exists" do
      expect(RiskProfile.count).to eq(0)
      profile = RiskProfile.current
      expect(profile).to be_persisted
      expect(profile.name).to eq("moderate")
      expect(RiskProfile.count).to eq(1)
    end

    it "always returns the same record" do
      first_call = RiskProfile.current
      second_call = RiskProfile.current
      expect(first_call.id).to eq(second_call.id)
    end
  end

  describe ".current_name" do
    it "returns the name of the current profile" do
      create(:risk_profile, :fearless)
      expect(RiskProfile.current_name).to eq("fearless")
    end

    it "returns moderate by default when no profile exists" do
      expect(RiskProfile.current_name).to eq("moderate")
    end
  end

  describe ".switch_to!" do
    it "switches to the specified profile" do
      create(:risk_profile, name: "moderate")
      RiskProfile.switch_to!("fearless", changed_by: "dashboard")

      expect(RiskProfile.current_name).to eq("fearless")
      expect(RiskProfile.current.changed_by).to eq("dashboard")
    end

    it "raises ArgumentError for invalid profile name" do
      create(:risk_profile)
      expect { RiskProfile.switch_to!("invalid") }.to raise_error(ArgumentError, /Invalid profile/)
    end

    it "updates the existing record instead of creating new ones" do
      create(:risk_profile, name: "moderate")
      expect { RiskProfile.switch_to!("fearless") }.not_to change { RiskProfile.count }
    end
  end

  describe "PROFILES constant" do
    it "includes all valid profile names" do
      expect(RiskProfile::PROFILES).to eq(%w[cautious moderate fearless])
    end
  end
end
