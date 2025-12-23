# Hyperliquid Gem Write Operations Specification

This document provides a detailed specification for implementing write (exchange) operations in the `marcomd/hyperliquid` Ruby gem. Currently, the gem only supports read operations via the Info API. This spec covers what's needed to implement order placement, cancellation, and other exchange operations.

## Overview

Hyperliquid uses EIP-712 typed data signing for authentication. All exchange operations require:
1. An Ethereum wallet private key
2. EIP-712 signature generation
3. POST request to the exchange endpoint

## Prerequisites

The gem already includes the `eth` gem as a dependency, which provides EIP-712 signing capabilities.

```ruby
# Already in hyperliquid.gemspec
spec.add_dependency "eth", "~> 0.5"
```

## Architecture

### Proposed Module Structure

```
lib/hyperliquid/
├── client.rb           # Existing - add exchange methods
├── info.rb             # Existing - Info API (read operations)
├── exchange.rb         # NEW - Exchange API (write operations)
├── signing/
│   ├── eip712.rb       # NEW - EIP-712 domain & types
│   └── signer.rb       # NEW - Signature generation
└── types/
    ├── order.rb        # NEW - Order type definitions
    └── action.rb       # NEW - Action type definitions
```

## EIP-712 Signing Implementation

### Domain Structure

```ruby
module Hyperliquid
  module Signing
    class EIP712
      MAINNET_CHAIN_ID = 42161  # Arbitrum One
      TESTNET_CHAIN_ID = 421614 # Arbitrum Sepolia

      def self.domain(mainnet:)
        {
          name: "Exchange",
          version: "1",
          chainId: mainnet ? MAINNET_CHAIN_ID : TESTNET_CHAIN_ID,
          verifyingContract: "0x0000000000000000000000000000000000000000"
        }
      end

      # L1 action domain (for most operations)
      def self.l1_action_domain(mainnet:)
        {
          chainId: mainnet ? MAINNET_CHAIN_ID : TESTNET_CHAIN_ID,
          name: "HyperliquidSignTransaction",
          version: "1"
        }
      end
    end
  end
end
```

### Type Definitions

```ruby
module Hyperliquid
  module Signing
    class EIP712
      # Order type structure
      ORDER_TYPES = {
        Order: [
          { name: "a", type: "uint256" },        # asset index
          { name: "b", type: "bool" },           # is_buy
          { name: "p", type: "uint256" },        # price (float string -> uint)
          { name: "s", type: "uint256" },        # size (float string -> uint)
          { name: "r", type: "bool" },           # reduce_only
          { name: "t", type: "uint8" },          # order_type (limit=0, trigger=1, etc.)
          { name: "i", type: "uint256" }         # time_in_force
        ]
      }

      # L1 Action type (wraps all exchange operations)
      L1_ACTION_TYPES = {
        HyperliquidTransaction_SpotSend: [
          { name: "hyperliquidChain", type: "string" },
          { name: "destination", type: "string" },
          { name: "token", type: "string" },
          { name: "amount", type: "string" },
          { name: "time", type: "uint64" }
        ],
        HyperliquidTransaction_Order: [
          { name: "hyperliquidChain", type: "string" },
          { name: "action", type: "string" },
          { name: "nonce", type: "uint64" }
        ]
      }
    end
  end
end
```

### Signer Implementation

```ruby
module Hyperliquid
  module Signing
    class Signer
      def initialize(private_key:, mainnet: true)
        @private_key = private_key
        @mainnet = mainnet
        @wallet = Eth::Key.new(priv: private_key)
      end

      def address
        @wallet.address.to_s
      end

      # Sign an L1 action (most exchange operations)
      def sign_l1_action(action, nonce)
        phantom_agent = construct_phantom_agent(action, nonce)

        typed_data = {
          types: {
            EIP712Domain: [
              { name: "name", type: "string" },
              { name: "version", type: "string" },
              { name: "chainId", type: "uint256" }
            ],
            Agent: [
              { name: "source", type: "string" },
              { name: "connectionId", type: "bytes32" }
            ]
          },
          primaryType: "Agent",
          domain: EIP712.l1_action_domain(mainnet: @mainnet),
          message: phantom_agent
        }

        sign_typed_data(typed_data)
      end

      # Sign user-initiated action (withdrawals, USD transfers)
      def sign_user_action(action)
        # Different signing flow for user actions
        # ...
      end

      private

      def construct_phantom_agent(action, nonce)
        connection_id = Eth::Util.keccak256(
          Eth::Abi.encode(
            ["(string,uint64)"],
            [[action_hash(action), nonce]]
          )
        )

        {
          source: @mainnet ? "a" : "b",
          connectionId: "0x" + connection_id.unpack1("H*")
        }
      end

      def action_hash(action)
        # Hash the action payload
        Eth::Util.keccak256(action.to_json)
      end

      def sign_typed_data(typed_data)
        # Use eth gem's EIP-712 signing
        encoded = Eth::Eip712.encode(typed_data)
        signature = @wallet.sign(encoded)

        {
          r: "0x" + signature[2..65],
          s: "0x" + signature[66..129],
          v: signature[130..131].to_i(16)
        }
      end
    end
  end
end
```

## Exchange Operations

### Order Placement

```ruby
module Hyperliquid
  class Exchange
    def initialize(client:, signer:)
      @client = client
      @signer = signer
    end

    # Place a single order
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @param is_buy [Boolean] True for buy, false for sell
    # @param size [String] Order size as string (e.g., "0.1")
    # @param limit_px [String] Limit price as string
    # @param order_type [Hash] Order type config
    # @param reduce_only [Boolean] Reduce-only flag
    # @param cloid [String, nil] Client order ID (optional)
    # @return [Hash] Order response
    def order(coin:, is_buy:, size:, limit_px:, order_type: { limit: { tif: "Gtc" } }, reduce_only: false, cloid: nil)
      nonce = timestamp_ms

      order_wire = {
        a: asset_index(coin),
        b: is_buy,
        p: float_to_wire(limit_px),
        s: float_to_wire(size),
        r: reduce_only,
        t: order_type_to_wire(order_type),
        c: cloid
      }.compact

      action = {
        type: "order",
        orders: [order_wire],
        grouping: "na"
      }

      signature = @signer.sign_l1_action(action, nonce)

      post_action(action, signature, nonce)
    end

    # Place multiple orders in a batch
    def bulk_orders(orders:, grouping: "na")
      nonce = timestamp_ms

      order_wires = orders.map do |o|
        {
          a: asset_index(o[:coin]),
          b: o[:is_buy],
          p: float_to_wire(o[:limit_px]),
          s: float_to_wire(o[:size]),
          r: o[:reduce_only] || false,
          t: order_type_to_wire(o[:order_type] || { limit: { tif: "Gtc" } }),
          c: o[:cloid]
        }.compact
      end

      action = {
        type: "order",
        orders: order_wires,
        grouping: grouping
      }

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end

    # Market order (aggressive limit IoC)
    def market_order(coin:, is_buy:, size:, slippage: 0.05)
      # Get current price and apply slippage
      mid = @client.all_mids[coin].to_f
      limit_px = is_buy ? mid * (1 + slippage) : mid * (1 - slippage)

      order(
        coin: coin,
        is_buy: is_buy,
        size: size.to_s,
        limit_px: format_price(limit_px),
        order_type: { limit: { tif: "Ioc" } }
      )
    end
  end
end
```

### Order Cancellation

```ruby
module Hyperliquid
  class Exchange
    # Cancel a single order
    # @param coin [String] Asset symbol
    # @param oid [Integer] Order ID
    def cancel(coin:, oid:)
      nonce = timestamp_ms

      action = {
        type: "cancel",
        cancels: [{ a: asset_index(coin), o: oid }]
      }

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end

    # Cancel by client order ID
    def cancel_by_cloid(coin:, cloid:)
      nonce = timestamp_ms

      action = {
        type: "cancelByCloid",
        cancels: [{ asset: asset_index(coin), cloid: cloid }]
      }

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end

    # Cancel all orders for an asset
    def cancel_all(coin: nil)
      nonce = timestamp_ms

      action = if coin
        { type: "cancel", cancels: [{ a: asset_index(coin), o: nil }] }
      else
        { type: "cancelAll" }
      end

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end
  end
end
```

### Leverage and Margin

```ruby
module Hyperliquid
  class Exchange
    # Update leverage for an asset
    # @param coin [String] Asset symbol
    # @param leverage [Integer] New leverage value
    # @param is_cross [Boolean] True for cross margin, false for isolated
    def update_leverage(coin:, leverage:, is_cross: true)
      nonce = timestamp_ms

      action = {
        type: "updateLeverage",
        asset: asset_index(coin),
        isCross: is_cross,
        leverage: leverage
      }

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end

    # Update isolated margin
    def update_isolated_margin(coin:, is_buy:, amount:)
      nonce = timestamp_ms

      action = {
        type: "updateIsolatedMargin",
        asset: asset_index(coin),
        isBuy: is_buy,
        ntli: amount  # Positive to add, negative to remove
      }

      signature = @signer.sign_l1_action(action, nonce)
      post_action(action, signature, nonce)
    end
  end
end
```

### Helper Methods

```ruby
module Hyperliquid
  class Exchange
    private

    def timestamp_ms
      (Time.now.to_f * 1000).to_i
    end

    def asset_index(coin)
      # Fetch from metadata or use cached mapping
      @asset_indices ||= build_asset_index_map
      @asset_indices[coin] || raise("Unknown asset: #{coin}")
    end

    def build_asset_index_map
      meta = @client.meta
      meta["universe"].each_with_index.map { |u, i| [u["name"], i] }.to_h
    end

    def float_to_wire(value)
      # Convert float string to wire format (integer representation)
      (value.to_f * 1e8).round.to_s
    end

    def format_price(price)
      # Format price with appropriate precision
      "%.5f" % price
    end

    def order_type_to_wire(order_type)
      # Convert order type hash to wire format
      if order_type[:limit]
        tif = order_type[:limit][:tif]
        case tif
        when "Gtc" then { limit: { tif: "Gtc" } }
        when "Ioc" then { limit: { tif: "Ioc" } }
        when "Alo" then { limit: { tif: "Alo" } }
        end
      elsif order_type[:trigger]
        { trigger: order_type[:trigger] }
      end
    end

    def post_action(action, signature, nonce)
      payload = {
        action: action,
        nonce: nonce,
        signature: signature,
        vaultAddress: nil
      }

      @client.post("/exchange", payload)
    end
  end
end
```

## Request/Response Format

### Order Request

```json
{
  "action": {
    "type": "order",
    "orders": [
      {
        "a": 0,
        "b": true,
        "p": "10000000000000",
        "s": "10000000",
        "r": false,
        "t": { "limit": { "tif": "Gtc" } },
        "c": null
      }
    ],
    "grouping": "na"
  },
  "nonce": 1703123456789,
  "signature": {
    "r": "0x...",
    "s": "0x...",
    "v": 28
  },
  "vaultAddress": null
}
```

### Order Response

```json
{
  "status": "ok",
  "response": {
    "type": "order",
    "data": {
      "statuses": [
        {
          "resting": {
            "oid": 12345
          }
        }
      ]
    }
  }
}
```

### Error Response

```json
{
  "status": "err",
  "response": "Insufficient margin"
}
```

## Test Coverage Requirements

### Unit Tests

```ruby
RSpec.describe Hyperliquid::Signing::Signer do
  describe "#sign_l1_action" do
    it "generates valid EIP-712 signature"
    it "uses correct domain for mainnet"
    it "uses correct domain for testnet"
  end
end

RSpec.describe Hyperliquid::Exchange do
  describe "#order" do
    it "places a limit buy order"
    it "places a limit sell order"
    it "handles reduce-only orders"
    it "includes client order ID when provided"
  end

  describe "#market_order" do
    it "applies slippage correctly for buys"
    it "applies slippage correctly for sells"
  end

  describe "#cancel" do
    it "cancels order by ID"
  end

  describe "#update_leverage" do
    it "updates cross margin leverage"
    it "updates isolated margin leverage"
  end
end
```

### Integration Tests (VCR)

```ruby
RSpec.describe "Hyperliquid Exchange Integration", :vcr do
  let(:client) { Hyperliquid::Client.new(testnet: true) }
  let(:exchange) { Hyperliquid::Exchange.new(client: client, private_key: test_key) }

  describe "order lifecycle" do
    it "places and cancels an order" do
      # Place order
      result = exchange.order(coin: "BTC", is_buy: true, size: "0.001", limit_px: "50000")
      expect(result["status"]).to eq("ok")
      order_id = result.dig("response", "data", "statuses", 0, "resting", "oid")

      # Cancel order
      cancel_result = exchange.cancel(coin: "BTC", oid: order_id)
      expect(cancel_result["status"]).to eq("ok")
    end
  end
end
```

## Implementation Checklist

- [ ] Create `lib/hyperliquid/signing/eip712.rb` with domain and type definitions
- [ ] Create `lib/hyperliquid/signing/signer.rb` with signature generation
- [ ] Create `lib/hyperliquid/exchange.rb` with exchange operations
- [ ] Add `post` method to `lib/hyperliquid/client.rb` for exchange endpoint
- [ ] Add exchange initialization to client (optional, with private key)
- [ ] Write unit tests for signer
- [ ] Write unit tests for exchange operations
- [ ] Record VCR cassettes for integration tests
- [ ] Update README with exchange usage examples
- [ ] Test on Hyperliquid testnet before mainnet

## Usage Example

```ruby
# Initialize client with exchange capabilities
client = Hyperliquid::Client.new(
  testnet: true,
  private_key: ENV["HYPERLIQUID_PRIVATE_KEY"]
)

# Place a limit order
result = client.exchange.order(
  coin: "BTC",
  is_buy: true,
  size: "0.01",
  limit_px: "95000",
  order_type: { limit: { tif: "Gtc" } }
)

# Place a market order
result = client.exchange.market_order(
  coin: "ETH",
  is_buy: false,
  size: "0.5",
  slippage: 0.03
)

# Cancel an order
client.exchange.cancel(coin: "BTC", oid: 12345)

# Update leverage
client.exchange.update_leverage(coin: "BTC", leverage: 10, is_cross: true)
```

## References

- [Hyperliquid API Documentation](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/exchange-endpoint)
- [Python SDK Reference](https://github.com/hyperliquid-dex/hyperliquid-python-sdk)
- [TypeScript SDK Reference](https://github.com/nktkas/hyperliquid)
- [EIP-712 Specification](https://eips.ethereum.org/EIPS/eip-712)
- [eth gem Documentation](https://github.com/q9f/eth.rb)
