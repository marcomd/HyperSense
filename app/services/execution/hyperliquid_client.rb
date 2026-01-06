# frozen_string_literal: true

module Execution
  # Wrapper around the hyperliquid gem for Hyperliquid DEX API interactions
  #
  # Provides:
  # - Connection management with automatic testnet/mainnet switching
  # - Credential management from ENV variables (HYPERLIQUID_ADDRESS, HYPERLIQUID_PRIVATE_KEY)
  # - Read operations (prices, positions, order book, candles)
  # - Write operations (order placement, cancellation) via EIP-712 signing
  # - Error handling and wrapping
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

    # Check if client is configured for read operations (balance, positions)
    # Only requires wallet address for public data queries
    # @return [Boolean]
    def read_configured?
      wallet_address.present?
    end

    # Check if client is configured for write operations (placing orders)
    # Requires both address and private key
    # @return [Boolean]
    def configured?
      private_key.present? && wallet_address.present?
    end

    # Get configured wallet address
    # @return [String]
    # @raise [ConfigurationError] if not configured
    def address
      raise ConfigurationError, "Hyperliquid address not configured. Add HYPERLIQUID_ADDRESS to .env" unless wallet_address.present?
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

    # === Write Operations ===

    # Place a market order on Hyperliquid
    # @param params [Hash] Order parameters
    #   - :symbol [String] Asset symbol (e.g., "BTC")
    #   - :side [String] "buy" or "sell"
    #   - :size [Numeric] Order size
    #   - :leverage [Integer] Leverage (optional, for logging)
    # @return [Hash] Order response from Hyperliquid
    # @raise [ConfigurationError] if credentials not configured
    # @raise [HyperliquidApiError] on API errors
    def place_order(params)
      validate_write_configuration!

      @logger.info "[HyperliquidClient] Placing order: #{params}"

      result = exchange.market_order(
        coin: params[:symbol],
        is_buy: params[:side] == "buy",
        size: params[:size].to_s,
        slippage:
      )

      @logger.info "[HyperliquidClient] Order response: #{result}"
      result
    rescue Hyperliquid::Error => e
      @logger.error "[HyperliquidClient] Order failed: #{e.class} - #{e.message}"
      raise HyperliquidApiError, "Order placement failed: #{e.message}"
    end

    # Cancel an order on Hyperliquid
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @param order_id [Integer] Order ID to cancel
    # @return [Hash] Cancel response from Hyperliquid
    # @raise [ConfigurationError] if credentials not configured
    # @raise [HyperliquidApiError] on API errors
    def cancel_order(coin, order_id)
      validate_write_configuration!

      @logger.info "[HyperliquidClient] Cancelling order #{order_id} for #{coin}"

      result = exchange.cancel(coin: coin, oid: order_id)

      @logger.info "[HyperliquidClient] Cancel response: #{result}"
      result
    rescue Hyperliquid::Error => e
      @logger.error "[HyperliquidClient] Cancel failed: #{e.class} - #{e.message}"
      raise HyperliquidApiError, "Order cancellation failed: #{e.message}"
    end

    # Update leverage for an asset
    # @param coin [String] Asset symbol (e.g., "BTC")
    # @param leverage [Integer] New leverage value
    # @return [Hash] Response (placeholder - not yet implemented in gem)
    # @note This method is a placeholder. Leverage is typically set at account level.
    def update_leverage(coin, leverage)
      @logger.warn "[HyperliquidClient] update_leverage called for #{coin} with leverage #{leverage}"
      @logger.warn "[HyperliquidClient] Note: Leverage update may need to be done via Hyperliquid UI or account settings"

      # The gem may not have this method yet - return informational response
      { status: "info", message: "Leverage is typically set at account level on Hyperliquid" }
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

    # Initialize SDK with private key for write operations
    # @return [Hyperliquid::SDK]
    def sdk
      @sdk ||= Hyperliquid::SDK.new(testnet: testnet?, private_key:)
    end

    # Info API client for read operations
    # @return [Hyperliquid::Info]
    def info
      sdk.info
    end

    # Exchange API client for write operations
    # @return [Hyperliquid::Exchange, nil] nil if private_key not configured
    def exchange
      sdk.exchange
    end

    # Get private key from environment
    # @return [String, nil]
    def private_key
      ENV.fetch("HYPERLIQUID_PRIVATE_KEY", nil)
    end

    # Get wallet address from environment
    # @return [String, nil]
    def wallet_address
      ENV.fetch("HYPERLIQUID_ADDRESS", nil)
    end

    # Get slippage from settings (default 0.5%)
    # @return [Float]
    def slippage
      Settings.hyperliquid.slippage || 0.005
    end

    # Validate that write operations can be performed
    # @raise [ConfigurationError] if private key not configured
    # @raise [ConfigurationError] if exchange not available
    # @raise [ConfigurationError] if derived address doesn't match expected address
    def validate_write_configuration!
      unless private_key.present?
        raise ConfigurationError, "HYPERLIQUID_PRIVATE_KEY not configured. Add it to .env file."
      end

      unless exchange.present?
        raise ConfigurationError, "Exchange client not available. Ensure private key is valid."
      end

      # Safety check: verify derived address matches expected address
      derived_address = exchange.address.downcase
      expected_address = wallet_address&.downcase

      if expected_address.present? && derived_address != expected_address
        @logger.error "[HyperliquidClient] Address mismatch! Derived: #{derived_address}, Expected: #{expected_address}"
        raise ConfigurationError,
              "Private key derives wrong address. " \
              "Expected: #{expected_address}, Got: #{derived_address}. " \
              "Check HYPERLIQUID_PRIVATE_KEY matches HYPERLIQUID_ADDRESS."
      end
    end

    # Wrap API calls with error handling
    # @yield Block to execute
    # @raise [HyperliquidApiError] on API errors
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
