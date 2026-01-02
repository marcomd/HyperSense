# frozen_string_literal: true

require "rails_helper"

RSpec.describe Risk::StopLossManager do
  let(:order_executor) { instance_double(Execution::OrderExecutor) }
  let(:hyperliquid_client) { instance_double(Execution::HyperliquidClient) }
  let(:stop_loss_manager) { described_class.new(client: hyperliquid_client, order_executor: order_executor) }

  before do
    allow(hyperliquid_client).to receive(:all_mids).and_return({
      "BTC" => "98000",
      "ETH" => "3200"
    })
  end

  describe "#check_all_positions" do
    context "when no positions exist" do
      it "returns empty results" do
        results = stop_loss_manager.check_all_positions
        expect(results[:triggered]).to be_empty
        expect(results[:checked]).to eq(0)
      end
    end

    context "with open positions" do
      let!(:btc_position) do
        create(:position,
          symbol: "BTC",
          direction: "long",
          status: "open",
          entry_price: 100_000,
          stop_loss_price: 95_000,
          take_profit_price: 110_000,
          current_price: 100_000
        )
      end

      context "when stop-loss is triggered" do
        let(:filled_order) { create(:order, :filled) }

        before do
          # Price dropped to 94,000 - below SL of 95,000
          allow(hyperliquid_client).to receive(:all_mids).and_return({ "BTC" => "94000" })
          allow(order_executor).to receive(:execute).and_return(filled_order)
        end

        it "triggers stop-loss and closes position" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to include(
            hash_including(
              position_id: btc_position.id,
              trigger: "stop_loss",
              price: 94_000
            )
          )
        end

        it "creates close decision and executes" do
          expect(order_executor).to receive(:execute).with(
            an_object_having_attributes(
              operation: "close",
              symbol: "BTC"
            )
          )

          stop_loss_manager.check_all_positions
        end

        it "updates position with close reason" do
          stop_loss_manager.check_all_positions

          btc_position.reload
          expect(btc_position.status).to eq("closed")
          expect(btc_position.close_reason).to eq("sl_triggered")
        end
      end

      context "when take-profit is triggered" do
        let(:filled_order) { create(:order, :filled) }

        before do
          # Price rose to 111,000 - above TP of 110,000
          allow(hyperliquid_client).to receive(:all_mids).and_return({ "BTC" => "111000" })
          allow(order_executor).to receive(:execute).and_return(filled_order)
        end

        it "triggers take-profit and closes position" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to include(
            hash_including(
              position_id: btc_position.id,
              trigger: "take_profit",
              price: 111_000
            )
          )
        end

        it "updates position with close reason" do
          stop_loss_manager.check_all_positions

          btc_position.reload
          expect(btc_position.close_reason).to eq("tp_triggered")
        end
      end

      context "when neither SL nor TP is triggered" do
        before do
          # Price at 98,000 - between SL (95k) and TP (110k)
          allow(hyperliquid_client).to receive(:all_mids).and_return({ "BTC" => "98000" })
        end

        it "does not trigger anything" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to be_empty
          expect(results[:checked]).to eq(1)
        end

        it "updates current price" do
          stop_loss_manager.check_all_positions

          btc_position.reload
          expect(btc_position.current_price).to eq(98_000)
        end
      end

      context "when position has no SL/TP" do
        let!(:eth_position) do
          create(:position,
            symbol: "ETH",
            direction: "long",
            status: "open",
            entry_price: 3000,
            stop_loss_price: nil,
            take_profit_price: nil,
            current_price: 3000
          )
        end

        it "skips positions without SL/TP" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to be_empty
          expect(results[:skipped]).to eq(1)
        end
      end
    end

    context "for short positions" do
      let!(:short_position) do
        create(:position,
          symbol: "BTC",
          direction: "short",
          status: "open",
          entry_price: 100_000,
          stop_loss_price: 105_000,  # SL above entry for shorts
          take_profit_price: 90_000, # TP below entry for shorts
          current_price: 100_000
        )
      end

      context "when stop-loss triggers" do
        let(:filled_order) { create(:order, :filled) }

        before do
          allow(hyperliquid_client).to receive(:all_mids).and_return({ "BTC" => "106000" })
          allow(order_executor).to receive(:execute).and_return(filled_order)
        end

        it "triggers stop-loss for short when price rises above SL" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to include(
            hash_including(trigger: "stop_loss")
          )
        end
      end

      context "when take-profit triggers" do
        let(:filled_order) { create(:order, :filled) }

        before do
          allow(hyperliquid_client).to receive(:all_mids).and_return({ "BTC" => "89000" })
          allow(order_executor).to receive(:execute).and_return(filled_order)
        end

        it "triggers take-profit for short when price drops below TP" do
          results = stop_loss_manager.check_all_positions

          expect(results[:triggered]).to include(
            hash_including(trigger: "take_profit")
          )
        end
      end
    end
  end

  describe "#check_position" do
    let(:position) do
      create(:position,
        symbol: "BTC",
        direction: "long",
        entry_price: 100_000,
        stop_loss_price: 95_000,
        take_profit_price: 110_000
      )
    end

    it "returns :stop_loss when SL triggered" do
      result = stop_loss_manager.check_position(position, current_price: 94_000)
      expect(result).to eq(:stop_loss)
    end

    it "returns :take_profit when TP triggered" do
      result = stop_loss_manager.check_position(position, current_price: 111_000)
      expect(result).to eq(:take_profit)
    end

    it "returns nil when neither triggered" do
      result = stop_loss_manager.check_position(position, current_price: 100_000)
      expect(result).to be_nil
    end
  end
end
