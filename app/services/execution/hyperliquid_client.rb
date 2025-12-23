# frozen_string_literal: true

module Execution
  # Wrapper around the hyperliquid gem for Hyperliquid DEX API interactions
  #
  # Provides:
  # - Connection management with automatic testnet/mainnet switching
  # - Credential management from Rails credentials
  # - Error handling and wrapping
  # - Rate limiting awareness
  #
  # Currently supports read operations only. Write operations require
  # EIP-712 signing which is not yet implemented in the gem.
  # See: docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md
  #
  class HyperliquidClient
    # Custom errors
    class HyperliquidApiError < StandardError; end
    class ConfigurationError < StandardError; end
    class WriteOperationNotImplemented < StandardError; end
    class UnknownAssetError < StandardError; end

    # Asset index mapping for Hyperliquid
    # These are the indices used by Hyperliquid's API for perpetuals
    ASSET_INDICES = {
      "BTC" => 0,
      "ETH" => 1,
      "SOL" => 5,
      "BNB" => 11
    }.freeze

    def initialize
      @logger = Rails.logger
    end

    # Check if client is properly configured
    # @return [Boolean]
    def configured?
      private_key.present? && wallet_address.present?
    end

    # Get configured wallet address
    # @return [String]
    # @raise [ConfigurationError] if not configured
    def address
      raise ConfigurationError, "Hyperliquid address not configured in credentials" unless wallet_address.present?
      wallet_address
    end

    # Check if running in testnet mode
    # @return [Boolean]
    def testnet?
      Settings.hyperliquid.testnet
    end

    # === Read Operations ===

    # Fetch user account state (positions, margin summary)
    # @param user_address [String] Wallet address
    # @return [Hash] User state with positions and margin info
    def user_state(user_address)
      with_error_handling do
        info.user_state(user_address)
      end
    end

    # Fetch open orders for user
    # @param user_address [String] Wallet address
    # @return [Array<Hash>] Open orders
    def open_orders(user_address)
      with_error_handling do
        info.open_orders(user_address)
      end
    end

    # Fetch recent fills (executed trades)
    # @param user_address [String] Wallet address
    # @return [Array<Hash>] Recent fills
    def user_fills(user_address)
      with_error_handling do
        info.user_fills(user_address)
      end
    end

    # Fetch asset metadata (all available assets)
    # @return [Hash] Asset metadata including universe
    def meta
      with_error_handling do
        info.meta
      end
    end

    # Fetch current mid prices for all assets
    # @return [Hash] Symbol => mid price mapping
    def all_mids
      with_error_handling do
        info.all_mids
      end
    end

    # Fetch order book for a coin
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @return [Hash] L2 order book
    def l2_book(coin)
      with_error_handling do
        info.l2_book(coin)
      end
    end

    # Fetch OHLCV candle data
    # @param coin [String] Asset symbol
    # @param interval [String] Candle interval (e.g., "1h", "4h", "1d")
    # @param start_time [Integer] Start timestamp in ms
    # @param end_time [Integer] End timestamp in ms
    # @return [Array<Hash>] Candle data
    def candles_snapshot(coin, interval, start_time, end_time)
      with_error_handling do
        info.candles_snapshot(coin, interval, start_time, end_time)
      end
    end

    # === Write Operations (Not Yet Implemented) ===

    # Place an order on Hyperliquid
    # @raise [WriteOperationNotImplemented]
    def place_order(_params)
      raise WriteOperationNotImplemented,
            "Order placement requires EIP-712 signing. " \
            "See docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md for implementation guide."
    end

    # Cancel an order
    # @raise [WriteOperationNotImplemented]
    def cancel_order(_coin, _order_id)
      raise WriteOperationNotImplemented,
            "Order cancellation requires EIP-712 signing. " \
            "See docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md for implementation guide."
    end

    # Update leverage for an asset
    # @raise [WriteOperationNotImplemented]
    def update_leverage(_coin, _leverage)
      raise WriteOperationNotImplemented,
            "Leverage updates require EIP-712 signing. " \
            "See docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md for implementation guide."
    end

    # === Helpers ===

    # Get asset index for a symbol
    # @param symbol [String] Asset symbol (e.g., "BTC")
    # @return [Integer] Asset index for Hyperliquid API
    # @raise [UnknownAssetError] if symbol not found
    def asset_index(symbol)
      ASSET_INDICES.fetch(symbol) do
        raise UnknownAssetError, "Unknown asset: #{symbol}. Known assets: #{ASSET_INDICES.keys.join(', ')}"
      end
    end

    private

    def sdk
      @sdk ||= Hyperliquid::SDK.new(testnet: testnet?)
    end

    def info
      sdk.info
    end

    def private_key
      Rails.application.credentials.dig(:hyperliquid, :private_key)
    end

    def wallet_address
      Rails.application.credentials.dig(:hyperliquid, :address)
    end

    def with_error_handling
      yield
    rescue Faraday::Error => e
      @logger.error "[HyperliquidClient] API error: #{e.class} - #{e.message}"
      raise HyperliquidApiError, "Hyperliquid API error: #{e.message}"
    rescue StandardError => e
      @logger.error "[HyperliquidClient] Unexpected error: #{e.class} - #{e.message}"
      raise HyperliquidApiError, "Unexpected error: #{e.message}"
    end
  end
end
