# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountBalance do
  describe "validations" do
    it "is valid with valid attributes" do
      account_balance = build(:account_balance)
      expect(account_balance).to be_valid
    end

    it "requires balance" do
      account_balance = build(:account_balance, balance: nil)
      expect(account_balance).not_to be_valid
      expect(account_balance.errors[:balance]).to include("can't be blank")
    end

    it "validates balance is numeric" do
      account_balance = build(:account_balance, balance: 10_000.0)
      expect(account_balance).to be_valid
    end

    it "requires event_type" do
      account_balance = build(:account_balance, event_type: nil)
      expect(account_balance).not_to be_valid
      expect(account_balance.errors[:event_type]).to include("can't be blank")
    end

    it "requires event_type to be valid" do
      %w[initial sync deposit withdrawal adjustment].each do |valid_type|
        account_balance = build(:account_balance, event_type: valid_type)
        expect(account_balance).to be_valid
      end

      account_balance = build(:account_balance, event_type: "invalid")
      expect(account_balance).not_to be_valid
      expect(account_balance.errors[:event_type]).to include("is not included in the list")
    end

    it "requires recorded_at" do
      account_balance = build(:account_balance, recorded_at: nil)
      # Should auto-set via callback
      account_balance.valid?
      expect(account_balance.recorded_at).to be_present
    end

    it "allows nil previous_balance" do
      account_balance = build(:account_balance, :initial, previous_balance: nil)
      expect(account_balance).to be_valid
    end

    it "allows nil delta" do
      account_balance = build(:account_balance, :initial, delta: nil)
      expect(account_balance).to be_valid
    end

    it "validates previous_balance is numeric when present" do
      account_balance = build(:account_balance, previous_balance: 9_000.0)
      expect(account_balance).to be_valid
    end

    it "validates delta is numeric when present" do
      account_balance = build(:account_balance, delta: 100.0)
      expect(account_balance).to be_valid
    end
  end

  describe "scopes" do
    describe ".initial_records" do
      it "returns only initial records" do
        initial = create(:account_balance, :initial)
        _sync = create(:account_balance, :sync)

        expect(described_class.initial_records).to contain_exactly(initial)
      end
    end

    describe ".syncs" do
      it "returns only sync records" do
        _initial = create(:account_balance, :initial)
        sync = create(:account_balance, :sync)

        expect(described_class.syncs).to contain_exactly(sync)
      end
    end

    describe ".deposits" do
      it "returns only deposit records" do
        _sync = create(:account_balance, :sync)
        deposit = create(:account_balance, :deposit)

        expect(described_class.deposits).to contain_exactly(deposit)
      end
    end

    describe ".withdrawals" do
      it "returns only withdrawal records" do
        _sync = create(:account_balance, :sync)
        withdrawal = create(:account_balance, :withdrawal)

        expect(described_class.withdrawals).to contain_exactly(withdrawal)
      end
    end

    describe ".adjustments" do
      it "returns only adjustment records" do
        _sync = create(:account_balance, :sync)
        adjustment = create(:account_balance, :adjustment)

        expect(described_class.adjustments).to contain_exactly(adjustment)
      end
    end

    describe ".recent" do
      it "orders by recorded_at descending" do
        older = create(:account_balance, recorded_at: 2.hours.ago)
        newer = create(:account_balance, recorded_at: 1.hour.ago)

        expect(described_class.recent.first).to eq(newer)
        expect(described_class.recent.last).to eq(older)
      end
    end

    describe ".chronological" do
      it "orders by recorded_at ascending" do
        newer = create(:account_balance, recorded_at: 1.hour.ago)
        older = create(:account_balance, recorded_at: 2.hours.ago)

        expect(described_class.chronological.first).to eq(older)
        expect(described_class.chronological.last).to eq(newer)
      end
    end

    describe ".by_event_type" do
      it "filters by event type" do
        deposit = create(:account_balance, :deposit)
        _withdrawal = create(:account_balance, :withdrawal)

        expect(described_class.by_event_type("deposit")).to contain_exactly(deposit)
      end
    end

    describe ".since" do
      it "returns records since specified time" do
        old = create(:account_balance, recorded_at: 2.days.ago)
        recent = create(:account_balance, recorded_at: 1.hour.ago)

        expect(described_class.since(1.day.ago)).to contain_exactly(recent)
        expect(described_class.since(3.days.ago)).to contain_exactly(old, recent)
      end
    end
  end

  describe "class methods" do
    describe ".latest" do
      it "returns the most recent balance record" do
        _older = create(:account_balance, recorded_at: 2.hours.ago)
        newer = create(:account_balance, recorded_at: 1.hour.ago)

        expect(described_class.latest).to eq(newer)
      end

      it "returns nil when no records exist" do
        expect(described_class.latest).to be_nil
      end
    end

    describe ".initial" do
      it "returns the first initial record" do
        initial = create(:account_balance, :initial, recorded_at: 1.day.ago)
        _sync = create(:account_balance, :sync, recorded_at: 1.hour.ago)

        expect(described_class.initial).to eq(initial)
      end

      it "returns nil when no initial record exists" do
        create(:account_balance, :sync)
        expect(described_class.initial).to be_nil
      end
    end

    describe ".total_deposits" do
      it "sums all deposit deltas" do
        create(:account_balance, :deposit, delta: 1_000.0)
        create(:account_balance, :deposit, delta: 2_000.0)
        create(:account_balance, :sync, delta: 500.0) # Should not be included

        expect(described_class.total_deposits).to eq(3_000.0)
      end

      it "returns 0 when no deposits exist" do
        create(:account_balance, :sync)
        expect(described_class.total_deposits).to eq(0)
      end
    end

    describe ".total_withdrawals" do
      it "sums all withdrawal deltas as positive number" do
        create(:account_balance, :withdrawal, delta: -1_000.0)
        create(:account_balance, :withdrawal, delta: -500.0)
        create(:account_balance, :sync, delta: -100.0) # Should not be included

        expect(described_class.total_withdrawals).to eq(1_500.0)
      end

      it "returns 0 when no withdrawals exist" do
        create(:account_balance, :sync)
        expect(described_class.total_withdrawals).to eq(0)
      end
    end

    describe ".current_balance" do
      it "returns balance from latest record" do
        create(:account_balance, balance: 10_000.0, recorded_at: 2.hours.ago)
        create(:account_balance, balance: 12_000.0, recorded_at: 1.hour.ago)

        expect(described_class.current_balance).to eq(12_000.0)
      end

      it "returns nil when no records exist" do
        expect(described_class.current_balance).to be_nil
      end
    end

    describe ".initial_capital" do
      it "returns balance from initial record" do
        create(:account_balance, :initial, balance: 10_000.0)
        create(:account_balance, :sync, balance: 12_000.0)

        expect(described_class.initial_capital).to eq(10_000.0)
      end

      it "returns nil when no initial record exists" do
        expect(described_class.initial_capital).to be_nil
      end
    end
  end

  describe "instance methods" do
    describe "#initial?" do
      it "returns true when event_type is initial" do
        account_balance = build(:account_balance, :initial)
        expect(account_balance.initial?).to be true
      end

      it "returns false when event_type is not initial" do
        account_balance = build(:account_balance, :sync)
        expect(account_balance.initial?).to be false
      end
    end

    describe "#sync?" do
      it "returns true when event_type is sync" do
        account_balance = build(:account_balance, :sync)
        expect(account_balance.sync?).to be true
      end

      it "returns false when event_type is not sync" do
        account_balance = build(:account_balance, :deposit)
        expect(account_balance.sync?).to be false
      end
    end

    describe "#deposit?" do
      it "returns true when event_type is deposit" do
        account_balance = build(:account_balance, :deposit)
        expect(account_balance.deposit?).to be true
      end

      it "returns false when event_type is not deposit" do
        account_balance = build(:account_balance, :sync)
        expect(account_balance.deposit?).to be false
      end
    end

    describe "#withdrawal?" do
      it "returns true when event_type is withdrawal" do
        account_balance = build(:account_balance, :withdrawal)
        expect(account_balance.withdrawal?).to be true
      end

      it "returns false when event_type is not withdrawal" do
        account_balance = build(:account_balance, :sync)
        expect(account_balance.withdrawal?).to be false
      end
    end

    describe "#adjustment?" do
      it "returns true when event_type is adjustment" do
        account_balance = build(:account_balance, :adjustment)
        expect(account_balance.adjustment?).to be true
      end

      it "returns false when event_type is not adjustment" do
        account_balance = build(:account_balance, :sync)
        expect(account_balance.adjustment?).to be false
      end
    end

    describe "#increased?" do
      it "returns true when delta is positive" do
        account_balance = build(:account_balance, delta: 100.0)
        expect(account_balance.increased?).to be true
      end

      it "returns false when delta is negative" do
        account_balance = build(:account_balance, delta: -100.0)
        expect(account_balance.increased?).to be false
      end

      it "returns false when delta is nil" do
        account_balance = build(:account_balance, delta: nil)
        expect(account_balance.increased?).to be false
      end

      it "returns false when delta is zero" do
        account_balance = build(:account_balance, delta: 0)
        expect(account_balance.increased?).to be false
      end
    end

    describe "#decreased?" do
      it "returns true when delta is negative" do
        account_balance = build(:account_balance, delta: -100.0)
        expect(account_balance.decreased?).to be true
      end

      it "returns false when delta is positive" do
        account_balance = build(:account_balance, delta: 100.0)
        expect(account_balance.decreased?).to be false
      end

      it "returns false when delta is nil" do
        account_balance = build(:account_balance, delta: nil)
        expect(account_balance.decreased?).to be false
      end

      it "returns false when delta is zero" do
        account_balance = build(:account_balance, delta: 0)
        expect(account_balance.decreased?).to be false
      end
    end
  end

  describe "callbacks" do
    describe "before_validation :set_recorded_at" do
      it "sets recorded_at on create if not provided" do
        freeze_time do
          account_balance = create(:account_balance, recorded_at: nil)
          expect(account_balance.recorded_at).to eq(Time.current)
        end
      end

      it "does not override recorded_at if provided" do
        specific_time = 1.day.ago
        account_balance = create(:account_balance, recorded_at: specific_time)
        expect(account_balance.recorded_at).to be_within(1.second).of(specific_time)
      end
    end
  end
end
