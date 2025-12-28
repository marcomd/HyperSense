# frozen_string_literal: true

require "rails_helper"

RSpec.describe Execution::PositionManager do
  let(:manager) { described_class.new }
  let(:mock_client) { instance_double(Execution::HyperliquidClient) }
  let(:test_address) { "0x1234567890abcdef1234567890abcdef12345678" }

  before do
    allow(Execution::HyperliquidClient).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:address).and_return(test_address)
    allow(mock_client).to receive(:configured?).and_return(true)
  end

  describe "#sync_from_hyperliquid" do
    let(:hyperliquid_positions) do
      {
        "assetPositions" => [
          {
            "position" => {
              "coin" => "BTC",
              "szi" => "0.1",
              "entryPx" => "100000.0",
              "markPx" => "102000.0",
              "unrealizedPnl" => "200.0",
              "liquidationPx" => "85000.0",
              "marginUsed" => "2000.0",
              "leverage" => { "value" => 5 }
            }
          },
          {
            "position" => {
              "coin" => "ETH",
              "szi" => "-1.0",
              "entryPx" => "3500.0",
              "markPx" => "3400.0",
              "unrealizedPnl" => "100.0",
              "liquidationPx" => "4200.0",
              "marginUsed" => "700.0",
              "leverage" => { "value" => 5 }
            }
          }
        ]
      }
    end

    before do
      allow(mock_client).to receive(:user_state).and_return(hyperliquid_positions)
    end

    it "creates new positions from Hyperliquid data" do
      expect { manager.sync_from_hyperliquid }
        .to change { Position.count }.by(2)
    end

    it "correctly parses long positions (positive size)" do
      manager.sync_from_hyperliquid

      btc_position = Position.find_by(symbol: "BTC")
      expect(btc_position.direction).to eq("long")
      expect(btc_position.size).to eq(0.1)
      expect(btc_position.entry_price).to eq(100_000)
    end

    it "correctly parses short positions (negative size)" do
      manager.sync_from_hyperliquid

      eth_position = Position.find_by(symbol: "ETH")
      expect(eth_position.direction).to eq("short")
      expect(eth_position.size).to eq(1.0) # Absolute value
    end

    it "updates existing open positions" do
      existing = create(:position, symbol: "BTC", status: "open", entry_price: 99_000)

      manager.sync_from_hyperliquid

      existing.reload
      expect(existing.entry_price).to eq(100_000)
      expect(existing.current_price).to eq(102_000)
    end

    it "closes positions that no longer exist in Hyperliquid" do
      orphan = create(:position, symbol: "SOL", status: "open")

      manager.sync_from_hyperliquid

      expect(orphan.reload.status).to eq("closed")
    end

    it "creates an execution log" do
      expect { manager.sync_from_hyperliquid }
        .to change { ExecutionLog.count }.by(1)

      log = ExecutionLog.last
      expect(log.action).to eq("sync_position")
      expect(log.status).to eq("success")
    end

    # Regression tests for nil handling (v0.13.1)
    context "when API returns incomplete position data" do
      let(:positions_with_missing_entry_px) do
        {
          "assetPositions" => [
            {
              "position" => {
                "coin" => "BTC",
                "szi" => "0.1",
                "entryPx" => nil, # Missing entry price
                "markPx" => "102000.0"
              }
            },
            {
              "position" => {
                "coin" => "ETH",
                "szi" => "-1.0",
                "entryPx" => "3500.0",
                "markPx" => "3400.0"
              }
            }
          ]
        }
      end

      let(:positions_with_missing_coin) do
        {
          "assetPositions" => [
            {
              "position" => {
                "coin" => nil, # Missing symbol
                "szi" => "0.1",
                "entryPx" => "100000.0"
              }
            }
          ]
        }
      end

      it "skips positions with missing entryPx without crashing" do
        allow(mock_client).to receive(:user_state).and_return(positions_with_missing_entry_px)

        expect { manager.sync_from_hyperliquid }.not_to raise_error
        expect(Position.count).to eq(1) # Only ETH position created
        expect(Position.find_by(symbol: "ETH")).to be_present
      end

      it "logs a warning for positions with missing entryPx" do
        allow(mock_client).to receive(:user_state).and_return(positions_with_missing_entry_px)
        allow(Rails.logger).to receive(:warn)

        manager.sync_from_hyperliquid

        expect(Rails.logger).to have_received(:warn).with(/missing entryPx for BTC/i)
      end

      it "skips positions with missing coin symbol without crashing" do
        allow(mock_client).to receive(:user_state).and_return(positions_with_missing_coin)

        expect { manager.sync_from_hyperliquid }.not_to raise_error
        expect(Position.count).to eq(0) # No positions created
      end

      it "skips positions with nil szi (size) gracefully" do
        positions = {
          "assetPositions" => [
            {
              "position" => {
                "coin" => "BTC",
                "szi" => nil,
                "entryPx" => "100000.0"
              }
            }
          ]
        }
        allow(mock_client).to receive(:user_state).and_return(positions)

        expect { manager.sync_from_hyperliquid }.not_to raise_error
        expect(Position.count).to eq(0) # Position skipped due to zero size
      end
    end
  end

  describe "#find_or_create_position" do
    it "returns existing open position if one exists" do
      existing = create(:position, symbol: "BTC", direction: "long", status: "open")

      result = manager.find_or_create_position("BTC", "long")

      expect(result).to eq(existing)
    end

    it "creates new position if none exists" do
      result = manager.find_or_create_position(
        "BTC", "long",
        size: 0.1,
        entry_price: 100_000,
        leverage: 5
      )

      expect(result).to be_persisted
      expect(result.symbol).to eq("BTC")
      expect(result.direction).to eq("long")
    end

    it "does not match closed positions" do
      _closed = create(:position, symbol: "BTC", direction: "long", status: "closed")

      result = manager.find_or_create_position(
        "BTC", "long",
        size: 0.1,
        entry_price: 100_000,
        leverage: 5
      )

      expect(result).to be_a_new_record.or be_persisted
      expect(Position.where(symbol: "BTC", status: "open").count).to eq(1)
    end
  end

  describe "#open_position" do
    it "creates a new open position" do
      result = manager.open_position(
        symbol: "BTC",
        direction: "long",
        size: 0.1,
        entry_price: 100_000,
        leverage: 5
      )

      expect(result).to be_persisted
      expect(result.status).to eq("open")
      expect(result.margin_used).to eq(2_000) # (0.1 * 100000) / 5
    end

    it "sets opened_at timestamp" do
      freeze_time do
        result = manager.open_position(
          symbol: "BTC",
          direction: "long",
          size: 0.1,
          entry_price: 100_000
        )

        expect(result.opened_at).to eq(Time.current)
      end
    end
  end

  describe "#close_position" do
    let(:position) { create(:position, status: "open") }

    it "marks position as closed" do
      manager.close_position(position)

      expect(position.reload.status).to eq("closed")
    end

    it "sets closed_at timestamp" do
      freeze_time do
        manager.close_position(position)

        expect(position.reload.closed_at).to eq(Time.current)
      end
    end
  end

  describe "#update_prices" do
    let(:mock_mids) do
      {
        "BTC" => "102000",
        "ETH" => "3550"
      }
    end

    before do
      allow(mock_client).to receive(:all_mids).and_return(mock_mids)
    end

    it "updates current prices for all open positions" do
      btc_pos = create(:position, symbol: "BTC", direction: "long",
                                  entry_price: 100_000, current_price: 100_000, size: 0.1)
      eth_pos = create(:position, symbol: "ETH", direction: "short",
                                  entry_price: 3500, current_price: 3500, size: 1)

      manager.update_prices

      expect(btc_pos.reload.current_price).to eq(102_000)
      expect(eth_pos.reload.current_price).to eq(3550)
    end

    it "recalculates unrealized PnL" do
      position = create(:position, symbol: "BTC", direction: "long",
                                   size: 0.1, entry_price: 100_000, current_price: 100_000)

      manager.update_prices

      position.reload
      expect(position.unrealized_pnl).to eq(200) # 0.1 * (102000 - 100000)
    end

    it "ignores positions for unknown symbols" do
      position = create(:position, symbol: "UNKNOWN", current_price: 100)

      expect { manager.update_prices }.not_to change { position.reload.current_price }
    end
  end

  describe "#has_open_position?" do
    it "returns true when open position exists for symbol" do
      create(:position, symbol: "BTC", status: "open")

      expect(manager.has_open_position?("BTC")).to be true
    end

    it "returns false when no open position exists" do
      create(:position, symbol: "BTC", status: "closed")

      expect(manager.has_open_position?("BTC")).to be false
    end

    it "can filter by direction" do
      create(:position, symbol: "BTC", direction: "long", status: "open")

      expect(manager.has_open_position?("BTC", direction: "long")).to be true
      expect(manager.has_open_position?("BTC", direction: "short")).to be false
    end
  end
end
