# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::BalanceSyncService do
  let(:mock_client) { instance_double(Execution::HyperliquidClient) }
  let(:mock_account_manager) { instance_double(Execution::AccountManager) }
  let(:test_address) { "0x1234567890abcdef1234567890abcdef12345678" }
  let(:service) { described_class.new(client: mock_client) }

  let(:account_state) do
    {
      account_value: 10_000.0,
      margin_used: 2_000.0,
      available_margin: 8_000.0,
      positions_count: 1,
      raw_response: {
        "crossMarginSummary" => {
          "accountValue" => "10000.0",
          "totalMarginUsed" => "2000.0",
          "totalRawUsd" => "8000.0"
        }
      }
    }
  end

  before do
    allow(mock_client).to receive(:address).and_return(test_address)
    allow(mock_client).to receive(:configured?).and_return(true)
    allow(Execution::AccountManager).to receive(:new).and_return(mock_account_manager)
    allow(mock_account_manager).to receive(:fetch_account_state).and_return(account_state)
  end

  describe "#sync!" do
    context "when client is not configured" do
      before do
        allow(mock_client).to receive(:configured?).and_return(false)
      end

      it "returns skipped status with reason" do
        result = service.sync!

        expect(result).to eq(skipped: true, reason: "not_configured")
      end

      it "does not create any records" do
        expect { service.sync! }.not_to change { AccountBalance.count }
      end
    end

    context "when no previous balance record exists (first sync)" do
      it "creates an initial balance record" do
        expect { service.sync! }.to change { AccountBalance.count }.by(1)
      end

      it "sets event_type to initial" do
        result = service.sync!

        expect(result[:event_type]).to eq("initial")
        expect(AccountBalance.latest.event_type).to eq("initial")
      end

      it "stores the current balance" do
        service.sync!

        expect(AccountBalance.latest.balance).to eq(10_000.0)
      end

      it "does not set previous_balance or delta" do
        service.sync!

        record = AccountBalance.latest
        expect(record.previous_balance).to be_nil
        expect(record.delta).to be_nil
      end

      it "stores hyperliquid data" do
        service.sync!

        expect(AccountBalance.latest.hyperliquid_data).to include("crossMarginSummary")
      end

      it "returns success result" do
        result = service.sync!

        expect(result[:created]).to be true
        expect(result[:balance]).to eq(10_000.0)
      end
    end

    context "when previous balance record exists" do
      let!(:previous_record) do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 1.hour.ago)
      end

      context "with no significant balance change" do
        before do
          allow(mock_account_manager).to receive(:fetch_account_state)
            .and_return(account_state.merge(account_value: 10_000.0))
        end

        it "skips recording" do
          result = service.sync!

          expect(result).to eq(skipped: true, reason: "no_change")
        end

        it "does not create new record" do
          expect { service.sync! }.not_to change { AccountBalance.count }
        end
      end

      context "with balance change from trading PnL" do
        let(:new_account_state) do
          account_state.merge(
            account_value: 10_100.0,
            raw_response: {
              "crossMarginSummary" => {
                "accountValue" => "10100.0",
                "totalMarginUsed" => "2000.0",
                "totalRawUsd" => "8100.0"
              }
            }
          )
        end

        before do
          allow(mock_account_manager).to receive(:fetch_account_state)
            .and_return(new_account_state)

          # Create a closed position with realized PnL matching the balance change
          create(:position, :closed,
            realized_pnl: 100.0,
            closed_at: 30.minutes.ago)
        end

        it "creates a sync record" do
          result = service.sync!

          expect(result[:event_type]).to eq("sync")
          expect(AccountBalance.latest.event_type).to eq("sync")
        end

        it "records the delta" do
          service.sync!

          record = AccountBalance.latest
          expect(record.balance).to eq(10_100.0)
          expect(record.previous_balance).to eq(10_000.0)
          expect(record.delta).to eq(100.0)
        end
      end

      context "with balance increase not explained by PnL (deposit detected)" do
        let(:new_account_state) do
          account_state.merge(
            account_value: 15_000.0,
            raw_response: {
              "crossMarginSummary" => {
                "accountValue" => "15000.0",
                "totalMarginUsed" => "2000.0",
                "totalRawUsd" => "13000.0"
              }
            }
          )
        end

        before do
          allow(mock_account_manager).to receive(:fetch_account_state)
            .and_return(new_account_state)
        end

        it "creates a deposit record" do
          result = service.sync!

          expect(result[:event_type]).to eq("deposit")
          expect(AccountBalance.latest.event_type).to eq("deposit")
        end

        it "records the deposit delta" do
          service.sync!

          record = AccountBalance.latest
          expect(record.balance).to eq(15_000.0)
          expect(record.delta).to eq(5_000.0)
        end

        it "includes notes about deposit detection" do
          service.sync!

          expect(AccountBalance.latest.notes).to include("deposit")
        end
      end

      context "with balance decrease not explained by PnL (withdrawal detected)" do
        let(:new_account_state) do
          account_state.merge(
            account_value: 7_000.0,
            raw_response: {
              "crossMarginSummary" => {
                "accountValue" => "7000.0",
                "totalMarginUsed" => "2000.0",
                "totalRawUsd" => "5000.0"
              }
            }
          )
        end

        before do
          allow(mock_account_manager).to receive(:fetch_account_state)
            .and_return(new_account_state)
        end

        it "creates a withdrawal record" do
          result = service.sync!

          expect(result[:event_type]).to eq("withdrawal")
          expect(AccountBalance.latest.event_type).to eq("withdrawal")
        end

        it "records the withdrawal delta" do
          service.sync!

          record = AccountBalance.latest
          expect(record.balance).to eq(7_000.0)
          expect(record.delta).to eq(-3_000.0)
        end

        it "includes notes about withdrawal detection" do
          service.sync!

          expect(AccountBalance.latest.notes).to include("withdrawal")
        end
      end
    end

    context "when API fails" do
      before do
        allow(mock_account_manager).to receive(:fetch_account_state)
          .and_raise(Execution::HyperliquidClient::HyperliquidApiError, "Connection failed")
      end

      it "raises the error" do
        expect { service.sync! }
          .to raise_error(Execution::HyperliquidClient::HyperliquidApiError)
      end

      it "does not create any records" do
        expect { service.sync! rescue nil }.not_to change { AccountBalance.count }
      end
    end
  end

  describe "#calculated_pnl" do
    context "when no records exist" do
      it "returns 0" do
        expect(service.calculated_pnl).to eq(0)
      end
    end

    context "with only initial record" do
      before do
        create(:account_balance, :initial, balance: 10_000.0)
      end

      it "returns 0 (no change yet)" do
        expect(service.calculated_pnl).to eq(0)
      end
    end

    context "with balance increase from trading" do
      before do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 1.day.ago)
        create(:account_balance, :sync, balance: 11_000.0, recorded_at: 1.hour.ago)
      end

      it "calculates PnL as current - initial" do
        expect(service.calculated_pnl).to eq(1_000.0)
      end
    end

    context "with deposits" do
      before do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 2.days.ago)
        create(:account_balance, :deposit, balance: 15_000.0, delta: 5_000.0, recorded_at: 1.day.ago)
        create(:account_balance, :sync, balance: 16_000.0, recorded_at: 1.hour.ago)
      end

      it "excludes deposits from PnL calculation" do
        # PnL = current (16k) - initial (10k) - deposits (5k) = 1k
        expect(service.calculated_pnl).to eq(1_000.0)
      end
    end

    context "with withdrawals" do
      before do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 2.days.ago)
        create(:account_balance, :withdrawal, balance: 8_000.0, delta: -2_000.0, recorded_at: 1.day.ago)
        create(:account_balance, :sync, balance: 9_000.0, recorded_at: 1.hour.ago)
      end

      it "excludes withdrawals from PnL calculation" do
        # PnL = current (9k) - initial (10k) + withdrawals (2k) = 1k
        expect(service.calculated_pnl).to eq(1_000.0)
      end
    end

    context "with both deposits and withdrawals" do
      before do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 3.days.ago)
        create(:account_balance, :deposit, balance: 15_000.0, delta: 5_000.0, recorded_at: 2.days.ago)
        create(:account_balance, :withdrawal, balance: 12_000.0, delta: -3_000.0, recorded_at: 1.day.ago)
        create(:account_balance, :sync, balance: 13_000.0, recorded_at: 1.hour.ago)
      end

      it "calculates PnL correctly" do
        # PnL = current (13k) - initial (10k) - deposits (5k) + withdrawals (3k) = 1k
        expect(service.calculated_pnl).to eq(1_000.0)
      end
    end

    context "with trading losses" do
      before do
        create(:account_balance, :initial, balance: 10_000.0, recorded_at: 1.day.ago)
        create(:account_balance, :sync, balance: 8_000.0, recorded_at: 1.hour.ago)
      end

      it "returns negative PnL" do
        expect(service.calculated_pnl).to eq(-2_000.0)
      end
    end
  end

  describe "#balance_history" do
    before do
      create(:account_balance, :initial, balance: 10_000.0, recorded_at: 3.days.ago)
      create(:account_balance, :deposit, balance: 15_000.0, delta: 5_000.0, recorded_at: 2.days.ago)
      create(:account_balance, :sync, balance: 16_000.0, delta: 1_000.0, recorded_at: 1.day.ago)
      create(:account_balance, :withdrawal, balance: 14_000.0, delta: -2_000.0, recorded_at: 1.hour.ago)
    end

    it "returns summary of balance history" do
      result = service.balance_history

      expect(result[:initial_balance]).to eq(10_000.0)
      expect(result[:current_balance]).to eq(14_000.0)
      expect(result[:total_deposits]).to eq(5_000.0)
      expect(result[:total_withdrawals]).to eq(2_000.0)
      expect(result[:calculated_pnl]).to eq(1_000.0)
      expect(result[:last_sync]).to be_present
    end
  end

  describe "threshold for deposit/withdrawal detection" do
    let!(:previous_record) do
      create(:account_balance, :initial, balance: 10_000.0, recorded_at: 1.hour.ago)
    end

    context "with change below threshold (rounding error)" do
      before do
        # $0.50 change - below $1 threshold
        allow(mock_account_manager).to receive(:fetch_account_state)
          .and_return(account_state.merge(account_value: 10_000.50))
      end

      it "creates a sync record, not deposit" do
        result = service.sync!

        expect(result[:event_type]).to eq("sync")
      end
    end

    context "with change above threshold and no matching PnL" do
      before do
        # $5 change - above $1 threshold, no PnL to explain it
        allow(mock_account_manager).to receive(:fetch_account_state)
          .and_return(account_state.merge(account_value: 10_005.0))
      end

      it "creates a deposit record" do
        result = service.sync!

        expect(result[:event_type]).to eq("deposit")
      end
    end
  end
end
