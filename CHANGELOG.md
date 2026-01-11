# Changelog

All notable changes to HyperSense.

## [1.0.1] - 2026-01-11

### Fixed
- **Rack Status Code Deprecation** - Changed `:unprocessable_entity` to `:unprocessable_content`
  - Updated `TradingModesController` and `RiskProfilesController` to use new status code
  - Updated corresponding request specs to expect `:unprocessable_content`
  - Fixes: "Status code :unprocessable_entity is deprecated and will be removed in a future version of Rack"

- **RubyLLM acts_as Deprecation** - Enabled new acts_as API in RubyLLM configuration
  - Added `config.use_new_acts_as = true` to `config/initializers/ruby_llm.rb`
  - Fixes: "RubyLLM's legacy acts_as API is deprecated and will be removed in RubyLLM 2.0.0"

### Technical Details
- Updated: `app/controllers/api/v1/trading_modes_controller.rb`
- Updated: `app/controllers/api/v1/risk_profiles_controller.rb`
- Updated: `spec/requests/api/v1/trading_modes_spec.rb`
- Updated: `spec/requests/api/v1/risk_profiles_spec.rb`
- Updated: `config/initializers/ruby_llm.rb`

## [1.0.0] - 2026-01-11

### Added
- **Peak Tracking & Profit Protection** - Smart exit decision support for the trading agent
  - Position model now tracks `peak_price` (best price since entry) and `peak_price_at` (when peak occurred)
  - Added `drawdown_from_peak_pct` to measure how far price has fallen from peak
  - Added `profit_drawdown_from_peak_pct` to detect when profits are fading
  - Added `minutes_since_peak` for time-based analysis

- **Trailing Stop Manager** - Automatic profit protection mechanism
  - New `Risk::TrailingStopManager` service that moves stop-loss as price moves favorably
  - Activates when position reaches profile-specific profit threshold (1.5-2%)
  - Trails behind peak price by profile-specific distance (0.8-1.5%)
  - Never moves stop-loss in unfavorable direction (only locks in more profit)
  - `RiskMonitoringJob` now includes trailing stop updates before SL/TP checks

- **Momentum Detection** - Trend reversal signals for the LLM agent
  - `ContextAssembler` now includes `momentum_signals` with RSI trend, MACD momentum, and RSI divergence
  - Bearish/bullish divergence detection (price vs RSI direction mismatch)
  - LLM agent uses momentum data to identify early exit opportunities

- **Profile-Specific TP Zone & Profit Protection** - Configurable take-profit behavior
  - New settings in `settings.yml` for each profile: `tp_zone_pct`, `profit_drawdown_alert_pct`, `trailing_stop`
  - Cautious: 3% TP zone, 25% profit alert, 1.5% trail distance
  - Moderate: 2% TP zone, 30% profit alert, 1% trail distance
  - Fearless: 1.5% TP zone, 40% profit alert, 0.8% trail distance
  - `ProfileService` accessors for all new settings

- **Enhanced Position Data for LLM** - Better context for close decisions
  - Distance metrics: `pct_to_stop_loss`, `pct_to_take_profit`, `is_in_tp_zone`, `is_near_sl`
  - Peak tracking data in context: peak price, drawdown, profit drawdown, minutes since peak
  - Trailing stop status: active flag, original stop-loss before trailing started

### Changed
- **LowLevelAgent CLOSE Rules** - Data-driven exit decisions
  - Updated system prompt with new CLOSE conditions using peak tracking and momentum data
  - Agent can now close based on: TP zone entry, profit drawdown from peak, momentum reversal, RSI divergence
  - Added momentum analysis section to user prompt
  - Enhanced position display with peak tracking, distance metrics, and trailing stop status

- **PositionManager** - Peak tracking integration
  - `update_prices` now also updates peak price for each position
  - Logs count of new peaks set during each price update

### Technical Details
- New files: `app/services/risk/trailing_stop_manager.rb`
- New migration: `add_peak_and_trailing_stop_to_positions` (peak_price, peak_price_at, trailing_stop_active, original_stop_loss_price)
- Updated: `position.rb`, `profile_service.rb`, `context_assembler.rb`, `position_manager.rb`, `risk_monitoring_job.rb`, `low_level_agent.rb`
- Updated: `config/settings.yml` with profile-specific profit protection settings

## [0.40.0] - 2026-01-11

### Added
- **Dashboard Decision-Position Linkage** - Added order/position data in Dashboard API
  - The DashboardController's `recent_decisions` method was not including order and position data
  - Added `includes(order: :position)` for eager loading to prevent N+1 queries
  - Added `order` and `position` serialization to match DecisionsController format
  - Also added missing fields: `executed`, `rejection_reason`, `leverage`, `stop_loss`, `take_profit`, `atr_value`, `next_cycle_interval`
  - Dashboard now correctly displays position P&L outcomes for linked decisions

### Technical Details
- Updated: `app/controllers/api/v1/dashboard_controller.rb`
- Added: `serialize_decision_order_summary`, `serialize_decision_position_summary`, `decision_position_outcome` private methods

## [0.39.0] - 2026-01-08

### Added
- **Trading Mode Control** - User-controlled trading modes with circuit breaker integration
  - Three modes: `enabled` (normal operation), `exit_only` (close positions only), `blocked` (complete halt)
  - Circuit breaker now automatically sets mode to `exit_only` when triggered
  - Users can override circuit breaker by switching back to `enabled` via dashboard
  - Real-time WebSocket updates when trading mode changes

- **TradingMode Model** - New singleton model for trading mode state
  - `TradingMode.current` - Returns current mode singleton
  - `TradingMode.switch_to!(mode, changed_by:, reason:)` - Changes mode and broadcasts update
  - Helper methods: `can_open?`, `can_close?`

- **TradingModesController** - REST API for trading mode management
  - `GET /api/v1/trading_mode/current` - Returns current mode and permissions
  - `PUT /api/v1/trading_mode/switch` - Changes mode, broadcasts via WebSocket

### Changed
- **CircuitBreaker** - Now sets TradingMode directly when triggered
  - Removed cooldown-based trading resumption (users now control when to resume)
  - `trigger!` method sets mode to `exit_only` with reason
  - `trading_allowed?` delegates to `TradingMode.current.can_open?`

- **TradingCycle** - Now checks TradingMode instead of CircuitBreaker
  - Step 0 checks if mode is `blocked` (complete halt)
  - `filter_and_approve` checks `can_open?` for opens, `can_close?` for closes

- **HealthController** - Enhanced response with trading mode details
  - Added `trading_mode`, `can_open_positions`, `can_close_positions` fields
  - `trading_allowed` now derived from mode (true if can open or close)

- **DashboardController** - Added `trading_mode` to dashboard response

- **DashboardChannel** - Added `broadcast_trading_mode_update` method

### Technical Details
- New files: `app/models/trading_mode.rb`, `app/controllers/api/v1/trading_modes_controller.rb`
- New migration: `create_trading_modes` table
- Updated: `risk/circuit_breaker.rb`, `trading_cycle.rb`, `health_controller.rb`, `dashboard_controller.rb`, `dashboard_channel.rb`
- Full test coverage: 985 examples, 0 failures

## [0.38.0] - 2026-01-08

### Added
- **Decision-Position Linkage** - Trading decisions now expose their linked order and position data
  - Added `has_one :order` association to `TradingDecision` model
  - Added `#position` and `#executed_order` helper methods to `TradingDecision`
  - Added `#outcome` method returning win/loss/breakeven/open/pending status
  - Added `#opening_decision` and `#closing_decision` methods to `Position` model
  - API responses now include full trade lifecycle data

### Changed
- **DecisionsController** - Enhanced API responses with order and position data
  - `serialize_decision` now includes `order` and `position` summaries
  - Position summary includes `outcome` field (win/loss/breakeven for closed positions)
  - Added eager loading with `includes(order: :position)` to prevent N+1 queries

- **PositionsController** - Enhanced API responses with decision context
  - `serialize_position` now includes `opening_decision` and `closing_decision` summaries
  - Added eager loading with `includes(orders: :trading_decision)`

### Technical Details
- Updated: `app/models/trading_decision.rb`, `app/models/position.rb`
- Updated: `app/controllers/api/v1/decisions_controller.rb`, `app/controllers/api/v1/positions_controller.rb`
- Added: Tests for new model methods and associations

## [0.37.2] - 2026-01-07

### Fixed
- **Solid Queue Running in Both Backend and Worker Containers** - Fixed Solid Queue plugin loading in Puma despite `SOLID_QUEUE_IN_PUMA: "false"`
  - Root cause: In Ruby, environment variables are always strings, and any non-empty string (including `"false"`) is truthy
  - The condition `if ENV["SOLID_QUEUE_IN_PUMA"]` evaluated to `true` because `"false"` is a truthy string
  - Changed condition to `if ENV.fetch("SOLID_QUEUE_IN_PUMA", "false") == "true"` for explicit string comparison
  - This ensures the worker container is the only process running Solid Queue jobs

### Technical Details
- Updated: `config/puma.rb`
- Ruby gotcha: `if "false"` is `true` because only `nil` and `false` (boolean) are falsy in Ruby

## [0.37.1] - 2026-01-06

### Fixed
- **Ollama Custom Models** - Fixed "Unknown model" error when using custom Ollama models
  - Added `assume_model_exists: true` flag for Ollama provider to skip registry validation
  - Ollama users can now use any locally downloaded model (e.g., `qwen3:8b`, `mistral`, etc.)
  - New `chat_options` private method in `LLM::Client` handles provider-specific initialization

### Technical Details
- Updated: `app/services/llm/client.rb`
- Updated test expectations in `spec/services/llm/client_spec.rb`

## [0.37.0] - 2026-01-05

### Added
- **Data Readiness Checker** - Trading is now blocked unless all critical data sources are available
  - New `Risk::ReadinessChecker` service validates data before trading decisions
  - Checks: valid MacroStrategy (not fallback), forecasts exist, fresh market data (<5 min), sentiment data
  - Configurable via `config/settings.yml` under `readiness:` section
  - Prevents trading with incomplete context when system is freshly deployed
  - 12 new tests for ReadinessChecker service

### Fixed
- **LLM JSON Extraction** - Improved JSON parsing to handle responses wrapped in explanatory text
  - `DecisionParser.extract_json` now uses 3-strategy approach: direct parse, code block extraction, regex extraction
  - Handles cases where LLM returns `"Here's my analysis: {...}"` instead of pure JSON
  - Added `EncodingError` to rescue clause (Oj raises this instead of ParseError in some cases)
  - 5 new test cases for JSON extraction from surrounding text

- **HighLevelAgent Retry Logic** - Added retry on parse failure to reduce fallback neutral strategies
  - Retries LLM call up to 2 times if JSON parsing fails
  - Logs warning on each retry attempt with error details
  - Only falls back to neutral strategy after all retries exhausted

### Changed
- **TradingCycle Workflow** - Added Step 3 (readiness check) between macro strategy refresh and running agents
  - Returns empty decisions if data not ready (similar to circuit breaker behavior)
  - Logs warning with specific missing data items

### Configuration
New `readiness` section in `config/settings.yml`:
```yaml
readiness:
  require_macro_strategy: true    # Require valid macro strategy
  require_forecasts: true         # Require at least one asset has recent forecasts
  require_fresh_market_data: true # Require recent market snapshots
  require_sentiment: true         # Require Fear & Greed sentiment data
  market_data_max_age_minutes: 5  # Market snapshots must be newer than this
  forecast_max_age_hours: 1       # Forecasts must be newer than this
```

### Technical Details
- New files: `app/services/risk/readiness_checker.rb`, `spec/services/risk/readiness_checker_spec.rb`
- Updated: `app/services/reasoning/decision_parser.rb`, `app/services/reasoning/high_level_agent.rb`, `app/services/trading_cycle.rb`
- New factory traits: `:active`, `:fallback` for `macro_strategy` factory
- All 41 new/updated tests passing

## No version - 2026-01-05

### Changed
- **Improved Architecture Documentation** - Rewrote the Architecture section in README for clarity
  - New detailed ASCII diagram showing chronological data flow (Data Ingestion → Agents → Risk → Execution)
  - Clear visualization of user settings (Risk Profiles) affecting trading behavior
  - Explicit wallet management and control emphasis in Execution Layer
- **Renamed "Execution Flow" to "How It Works"** - Complete rewrite with 6 subsections:
  - Data Collection: What MarketSnapshotJob collects and from which sources
  - Technical Indicators: Simple explanations of EMA, RSI, MACD, ATR, Pivot Points
  - External Data Sources: Fear & Greed Index, News, Whale Alerts
  - The Two-Agent System: High-Level and Low-Level agents with weighted inputs
  - Risk Profiles: User settings table with captain/rudder analogy
  - Trade Execution & Wallet Management: Full control emphasis, paper vs live modes

## [0.36.0] - 2026-01-04

### Added
- **Capital % ROI in Dashboard** - Account Summary now returns return on initial capital percentage
  - New `capital_pnl_percent` field in dashboard API response
  - Calculates ROI as `(calculated_pnl / initial_balance) * 100`
  - Returns `nil` when initial_balance is not available or zero
  - 4 new request specs for capital_pnl_percent edge cases

### Fixed
- **Balance Sync in Paper Trading** - Balance sync now runs in paper trading mode
  - Previously, both balance sync and position sync were skipped in paper trading
  - Now only position sync is skipped (to preserve paper positions)
  - This allows initial_balance to be recorded for ROI calculation

### Supports Frontend (0.18.0)

## [0.35.0] - 2026-01-04

### Added
- **Risk Profile Audit Trail** - Trading decisions now store which risk profile was active at creation time
  - New `risk_profile_name` column on `trading_decisions` table (default: `moderate`)
  - `LowLevelAgent` saves profile name when creating decisions
  - `DecisionsController` serializes `risk_profile_name` in API responses
  - Enables debugging when users switch profiles mid-session

### Supports Frontend (0.16.1)

## [0.34.0] - 2026-01-04

### Added
- **Risk Profile System** - User-selectable trading style profiles (Cautious/Moderate/Fearless)
  - New `risk_profiles` database table with singleton pattern
  - `RiskProfile` model for profile persistence and switching
  - `Risk::ProfileService` for centralized profile parameter access
  - API endpoints: `GET /api/v1/risk_profile/current`, `PUT /api/v1/risk_profile/switch`
  - WebSocket broadcast for real-time profile updates
  - Profile-aware settings throughout the trading system

### Changed
- **Dynamic LLM System Prompt** - RSI thresholds now vary by active risk profile
  - Cautious: RSI 35-65, 70% confidence, 2x leverage, max 3 positions
  - Moderate (default): RSI 30-70, 60% confidence, 3x leverage, max 5 positions
  - Fearless: RSI 25-75, 50% confidence, 5x leverage, max 7 positions
- **MarketSnapshot** - `rsi_signal` now uses profile-specific thresholds
- **RiskManager** - All risk parameters now sourced from active profile
- **ContextAssembler** - Trading context includes active profile name
- **DashboardController** - Dashboard response includes `risk_profile` object

### Technical Details
- New files: `app/models/risk_profile.rb`, `app/services/risk/profile_service.rb`, `app/controllers/api/v1/risk_profiles_controller.rb`
- Updated `config/settings.yml` with `risk_profiles` presets
- Added `DashboardChannel.broadcast_risk_profile_update` for WebSocket
- 12 new request specs for risk profile API

## [0.33.7] - 2026-01-03

### Fixed
- **Hyperliquid Testnet → Mainnet** - Switched from testnet to mainnet for accurate market prices
  - Reason: Performance testing capabilities on the testnet have been saturated, as trades were being thwarted by price discrepancies from real ones, which were causing the risk manager (SL and TP) to behave in an unrealistic manner. To continue testing, it is necessary to switch to the mainnet, initially in "paper trading" mode. This fix addresses an issue that occurred in this mode.
  - Testnet uses simulated prices that diverge significantly from real market
  - Mainnet prices now align with Binance data (both track real market)
  - Root cause of false stop-loss triggers (testnet price divergence)
- **Paper Trading Position Sync** - Positions no longer deleted when paper trading
  - Added `return if Settings.trading.paper_trading` guard in `TradingCycle#sync_positions_if_configured`
  - Paper positions now preserved locally instead of being orphaned by exchange sync
  - Enables safe testing with real mainnet prices without losing paper positions

### Changed
- `config/settings.yml` - `hyperliquid.testnet: false` (was `true`)
- `app/services/trading_cycle.rb` - Skip position sync in paper trading mode

## [0.33.6] - 2026-01-03

### Added
- **FactoryBot Environment Guard** - All 8 factory files now raise error if used outside test environment
  - Prevents accidental test data contamination in development/production
  - Error message: "FactoryBot should only be used in test environment!"
  - Files protected: positions, orders, trading_decisions, macro_strategies, market_snapshots, forecasts, execution_logs, account_balances

## [0.33.5] - 2026-01-03

### Fixed
- **Zeitwerk Autoloading** - Fixed `LLM::Errors` constant not found error in CI/production
  - Restructured `LLM::Error` → `LLM::Errors::Base` to match Zeitwerk naming conventions
  - Error classes now under `LLM::Errors::` namespace (RateLimitError, APIError, ConfigurationError, InvalidResponseError)
  - Removed `require_relative` from client.rb (Zeitwerk handles autoloading)

### Changed
- **GitHub Actions CI** - Added RSpec test job to CI workflow
  - Tests now run on every PR and push to master
  - Uses PostgreSQL 16 service container
  - Changed `db:create db:migrate` to `db:prepare` for multi-database support

## [0.33.4] - 2026-01-02

### Fixed
- **Account Summary Aggregated Volatility** - Dashboard now shows highest volatility across all assets
  - Previously showed the latest decision's symbol-specific volatility (regression from 0.33.3)
  - Now derives aggregated level from `next_cycle_interval` (e.g., if SOL is "medium", shows "medium")
  - Added `level_from_interval` helper to map interval back to volatility level

## [0.33.3] - 2026-01-02

### Fixed

- **Per-Symbol ATR Values** - Each trading decision now stores its own symbol-specific ATR percentage
  - Previously all decisions in a cycle got the same ATR from the most volatile asset
  - Now BTC decisions show BTC's ATR (e.g., 0.6%), ETH shows ETH's ATR (e.g., 0.75%), etc.
  - Job scheduling still uses highest volatility (smallest interval) across all assets

## [0.33.2] - 2026-01-02

### Fixed
- **Multiple Active MacroStrategies** - Only one MacroStrategy should be active at a time
  - When `MacroStrategyJob` creates a new strategy, it now expires all previous non-stale strategies
  - Sets `valid_until = Time.current` on previous strategies so they become stale immediately
  - Applied to both successful LLM responses and fallback strategies
  - Added `expire_previous_strategies` private method to `HighLevelAgent`

## [0.33.1] - 2026-01-02

### Fixed
- **ATR Value Display** - Fixed incorrect ATR percentage display in Trading Decisions page
  - Was storing raw `atr_value` instead of `atr_percentage` in TradingDecision
  - Frontend multiplies by 100 for percentage display (e.g., 0.025 → 2.50%)
  - Previously showed incorrect values like 131% instead of 1.31%

## [0.33.0] - 2026-01-02

### Added
- **EMA 200 Indicator** - Added 200-period Exponential Moving Average for long-term trend analysis
  - Enables Golden Cross / Death Cross detection (50 EMA crossing 200 EMA)
  - Price above/below 200 EMA defines bull/bear market structure
  - Displayed in MarketOverview dashboard card
  - Available in LLM context for trading decisions

### Changed
- **Candle Fetch Limit** - Increased from 150 to 250 hourly candles in MarketSnapshotJob
  - Ensures EMA 200 has sufficient data immediately (Binance API allows up to 1000)

### Technical Details
- Updated `Indicators::Calculator.calculate_all` to include `ema_200`
- Updated `Reasoning::ContextAssembler` with `ema_200` and `above_ema_200` signal
- Updated `Reasoning::HighLevelAgent` prompt to display `Above EMA-200` for each asset
- Updated `Reasoning::LowLevelAgent` prompt to display EMA-100, EMA-200 values and signals
- Updated `MarketDataController` and `DashboardController` API responses
- Added `above_ema_200` to MarketOverview frontend component
- New test coverage for EMA 200 calculation

### Supports Frontend (0.15.0)

## [0.32.0] - 2026-01-02

### Added
- **RSI Entry Filters** - Prevent opening positions at extreme RSI levels
  - Block long entries when RSI > 70 (overbought)
  - Block short entries when RSI < 30 (oversold)
  - Code-level enforcement in TradingCycle.filter_and_approve
- **Direction Independence from Macro** - Allow shorts during bullish macro and longs during bearish macro
  - Technical signals can override macro bias when strong (RSI extreme + MACD divergence)
  - Enables the agent to capture both directional moves
- **Improved Close Rules** - Prevent premature position exits
  - Close only when: price within 1% of SL/TP, or confirmed trend reversal (RSI crosses 50 AND MACD histogram changes sign)
  - Minimum 30-minute hold time before close (unless SL/TP triggered)
  - Removed "technical deterioration" as valid close reason

### Changed
- **Risk/Reward Ratio** - Lowered minimum from 2.0 to 1.5 to allow more trades
  - Updated DEFAULT_MIN_RISK_REWARD_RATIO in RiskManager
  - Updated settings.yml default value

### Technical Details
- Updated SYSTEM_PROMPT in `Reasoning::LowLevelAgent` with new rules
- Added RSI validation in `TradingCycle#filter_and_approve`
- New spec file: `spec/services/trading_cycle_spec.rb`
- Updated `spec/services/risk/risk_manager_spec.rb` for new R/R ratio

## [0.31.0] - 2026-01-02

### Added
- **Orders API** - REST endpoints for order history and statistics
  - `GET /api/v1/orders` - List orders with filters (status, symbol, side, order_type, date range)
  - `GET /api/v1/orders/:id` - Single order with full details including linked decision/position
  - `GET /api/v1/orders/active` - Pending and submitted orders
  - `GET /api/v1/orders/stats` - Order statistics (counts by status/side/type, fill rate, slippage)
- **Account Balances API** - REST endpoints for balance history and PnL summary
  - `GET /api/v1/account_balances` - List balance records with filters (event_type, date range)
  - `GET /api/v1/account_balances/:id` - Single balance record with Hyperliquid data
  - `GET /api/v1/account_balances/summary` - Current balance summary with calculated PnL

### Technical Details
- `Api::V1::OrdersController` - Orders API with filtering, pagination, and statistics
- `Api::V1::AccountBalancesController` - Balance history API with summary endpoint
- Full test coverage for both controllers (38 new tests)

### Supports Frontend (0.14.0)

## [0.30.0] - 2026-01-02

### Added
- **Balance Tracking System** - Track account balance history for accurate PnL calculation
  - `AccountBalance` model - Stores balance snapshots with event classification
  - `Execution::BalanceSyncService` - Syncs balance from Hyperliquid, detects deposits/withdrawals
  - Automatic balance sync during each TradingCycle
- **Deposit/Withdrawal Detection** - Distinguishes external funds from trading gains/losses
  - Compares balance changes with expected PnL from closed positions
  - Classifies events as: initial, sync, deposit, withdrawal, adjustment
- **Calculated PnL** - Accurate all-time PnL that accounts for deposits/withdrawals
  - Formula: `current_balance - initial_balance - deposits + withdrawals`
  - Dashboard now shows `calculated_pnl` alongside legacy `all_time_pnl`
- **Balance History in Dashboard** - New `balance_history` object in account summary
  - `initial_balance` - Starting capital (first recorded balance)
  - `total_deposits` - Sum of all detected deposits
  - `total_withdrawals` - Sum of all detected withdrawals
  - `last_sync` - Timestamp of last balance sync

### Technical Details
- Migration: `CreateAccountBalances` with JSONB for raw Hyperliquid data
- `AccountBalance` model with scopes: deposits, withdrawals, syncs, initial_records
- `BalanceSyncService#sync!` - Main sync method, returns event type and balance
- `BalanceSyncService#calculated_pnl` - Returns accurate PnL excluding deposits/withdrawals
- `TradingCycle#sync_balance` - Integrated at start of position sync
- `DashboardController#account_summary` - Now includes calculated_pnl and balance_history

## [0.29.0] - 2026-01-02

### Added
- **Hyperliquid Account Data in Dashboard** - Exchange balance and account info now shown in Account Summary
  - `hyperliquid.balance` - Current account value from exchange API
  - `hyperliquid.available_margin` - Available margin for trading
  - `hyperliquid.margin_used` - Margin currently in use
  - `hyperliquid.positions_count` - Number of positions on exchange
  - `hyperliquid.configured` - Whether Hyperliquid credentials are set
- **All-Time PnL Tracking** - Dashboard now shows total realized + unrealized PnL from all positions
  - `total_realized_pnl` - Sum of realized PnL from all closed positions
  - `all_time_pnl` - Combined realized + unrealized PnL
- **Testnet Mode Indicator** - `testnet_mode` field shows when using Hyperliquid testnet
- **Enhanced Position Sync Logging** - Debug logs now show account state during position sync

### Technical Details
- `DashboardController#fetch_hyperliquid_account_data` - Fetches account state from Hyperliquid
- `PositionManager#sync_from_hyperliquid` - Now logs testnet status and account value

### Supports Frontend (0.13.0)

## [0.28.0] - 2026-01-02

### Added
- **Tunnel Configuration via Environment Variables** - Configurable remote access for development
  - `BACKEND_TUNNEL_HOST` - Hostname for Rails host authorization (e.g., `your-tunnel.ngrok-free.app`)
  - `FRONTEND_TUNNEL_URL` - Full URL for CORS and ActionCable origins (e.g., `https://your-tunnel.pinggy.link`)
  - Updated `.env.example` with tunnel configuration section

### Changed
- **Dynamic Host Authorization** - `config.hosts` now reads from `BACKEND_TUNNEL_HOST` env variable
- **Dynamic CORS Origins** - `cors.rb` now uses `FRONTEND_TUNNEL_URL` for allowed origins
- **Dynamic ActionCable Origins** - `allowed_request_origins` reads from `FRONTEND_TUNNEL_URL`

### Technical Details
- `config/environments/development.rb` - Conditionally adds tunnel hosts from ENV
- `config/initializers/cors.rb` - Uses `FRONTEND_TUNNEL_URL` or `FRONTEND_URL` for origins

### Supports Frontend (0.12.0)

## [0.27.0] - 2026-01-01

### Changed
- **Health Endpoint as Single Source of Truth** - `/api/v1/health` now provides all app-wide status
  - Added `trading_allowed` field (circuit breaker status) to health endpoint
  - Removed `trading_allowed` from dashboard's `circuit_breaker` object (DRY principle)
  - Frontend uses `/health` for Header status indicators across all pages

### API Changes
- `GET /api/v1/health` - Now includes `trading_allowed` boolean:
  ```json
  {
    "status": "ok",
    "version": "0.27.0",
    "environment": "development",
    "paper_trading": false,
    "trading_allowed": true,
    "timestamp": "2026-01-01T14:30:00Z"
  }
  ```
- `GET /api/v1/dashboard` - Account `circuit_breaker` no longer includes `trading_allowed`:
  ```json
  {
    "circuit_breaker": {
      "daily_loss": -50.0,
      "consecutive_losses": 0
    }
  }
  ```

### Supports Frontend (0.10.0)

## [0.26.0] - 2026-01-01

### Added
- **ATR in Macro Strategy Context** - ATR indicator now included in high-level agent reasoning
  - `MarketSnapshot#atr_signal` - Returns volatility classification (:low_volatility, :normal_volatility, :high_volatility, :very_high_volatility)
  - `ContextAssembler` - Now includes `atr_14` value and `atr` signal in technical indicators
  - `HighLevelAgent` - Displays ATR value with volatility classification in assets overview prompt
  - Uses 4-band volatility thresholds aligned with dynamic scheduling (< 1%, 1-2%, 2-3%, >= 3%)

### Changed
- `MarketSnapshot` - Added ATR threshold constants for volatility classification
- Factory `:market_snapshot` - Now includes `atr_14` indicator with volatility traits

## [0.25.0] - 2026-01-01

### Added
- **Volatility Intervals in Dashboard API** - Dashboard now exposes configured intervals for each volatility level
  - `DashboardController#build_volatility_info` - Returns `intervals` object with timing configuration
  - Enables frontend to display actual interval values without hardcoding
  - Example response: `intervals: { very_high: 3, high: 6, medium: 12, low: 25 }`

### API Changes
- `GET /api/v1/dashboard` - Account summary `volatility_info` now includes `intervals` field:
  ```json
  {
    "volatility_info": {
      "volatility_level": "medium",
      "atr_value": 0.015,
      "next_cycle_interval": 12,
      "next_cycle_at": "2026-01-01T14:30:00Z",
      "last_decision_at": "2026-01-01T14:18:00Z",
      "intervals": {
        "very_high": 3,
        "high": 6,
        "medium": 12,
        "low": 25
      }
    }
  }
  ```

### Supports Frontend (0.9.0)

## [0.24.0] - 2026-01-01

### Added
- **ATR Volatility API Exposure** - Volatility information now available in API responses
  - `DecisionsController` - Serializes `volatility_level`, `atr_value`, `next_cycle_interval`
  - `DashboardController` - Account summary includes `volatility_info` from latest decision
  - `DashboardController` - Recent decisions now include `volatility_level` for dashboard display
  - New filter: `volatility_level` parameter for `/api/v1/decisions` endpoint
  - `llm_model` moved from list serialization to detailed view only

### Changed
- **Dynamic Trading Cycle Health Threshold** - `system_status.trading_cycle.healthy` now uses
  dynamic threshold based on `next_cycle_interval` + 2 min buffer instead of hardcoded 15 min
  - Prevents false "unhealthy" status when using longer intervals (e.g., 25 min for low volatility)

### API Changes
- `GET /api/v1/decisions` - Now includes volatility fields in response
- `GET /api/v1/decisions?volatility_level=high` - New filter parameter
- `GET /api/v1/dashboard` - Account summary includes `volatility_info` object with:
  - `volatility_level` - Current volatility classification
  - `atr_value` - Raw ATR percentage
  - `next_cycle_interval` - Minutes until next trading cycle
  - `next_cycle_at` - ISO8601 timestamp of next scheduled cycle
  - `last_decision_at` - When the latest decision was made
- `GET /api/v1/dashboard` - Recent decisions now include `volatility_level`

### Supports Frontend (0.8.0)

## [0.23.0] - 2025-12-31

### Added
- **Dynamic Volatility-Based Job Scheduling** - Trading cycle interval now adjusts based on market volatility
  - `Indicators::Calculator#atr` - ATR (Average True Range) indicator for volatility measurement
  - `Indicators::VolatilityClassifier` - Classifies ATR into 4 levels with corresponding intervals
  - `BootstrapTradingCycleJob` - Safety net job to ensure trading cycle chain is running
  - Volatility levels: Very High (3 min), High (6 min), Medium (12 min), Low (25 min)
  - TradingDecision gains `volatility_level`, `atr_value`, `next_cycle_interval` columns
  - ForecastJob now runs 1 minute before each TradingCycleJob for fresh forecasts

### Changed
- `TradingCycleJob` - Now self-scheduling with dynamic intervals based on ATR volatility
- `ForecastJob` - Removed from recurring.yml, now triggered by TradingCycleJob
- `config/recurring.yml` - Added BootstrapTradingCycleJob (every 30 min safety net)

### Configuration
New `volatility` section in `config/settings.yml`:
```yaml
volatility:
  thresholds:
    very_high: 0.03   # >= 3% ATR
    high: 0.02        # >= 2% ATR
    medium: 0.01      # >= 1% ATR
  intervals:
    very_high: 3      # minutes
    high: 6
    medium: 12
    low: 25
  default_interval: 12
```

### Technical Details
- 1 new database migration (`add_volatility_to_trading_decisions`)
- ATR calculated using 14-period EMA of True Range
- Bootstrap mechanism ensures chain restarts after app/worker restart
- `ensure` block guarantees next job is always scheduled

## [0.22.0] - 2025-12-31

### Added
- **OpenAI provider support** - Added OpenAI as a new LLM provider option
  - Supports `gpt-5.2` (default) and `gpt-5-mini` models
  - Configure via `LLM_PROVIDER=openai` environment variable
  - Requires `OPENAI_API_KEY` and optional `OPENAI_MODEL`
  - Full cost tracking integration with pricing: $1.75/$14.00 per 1M tokens (gpt-5.2)
  - 6 new tests for OpenAI provider support

### Configuration
New environment variables:
```bash
LLM_PROVIDER=openai
OPENAI_API_KEY=your_openai_api_key
OPENAI_MODEL=gpt-5.2  # or gpt-5-mini
```

New cost configuration in `config/settings.yml`:
```yaml
costs:
  llm:
    openai:
      gpt-5.2:
        input_per_million: 1.75
        output_per_million: 14.00
      gpt-5-mini:
        input_per_million: 0.25
        output_per_million: 2.00
```

## [0.21.1] - 2025-12-31

### Fixed
- **Dashboard reasoning truncation** - Removed server-side truncation of decision reasoning text
  - Frontend now receives full reasoning text and handles truncation/expansion in UI
  - Supports the new expandable "show more" feature in the dashboard

## [0.21.0] - 2025-12-31

### Added
- **Cost Management System** - On-the-fly cost tracking for trading fees, LLM usage, and server costs
  - `Costs::Calculator` - Main orchestrator combining all cost types, calculates net P&L
  - `Costs::TradingFeeCalculator` - Calculates entry/exit fees based on position notional value
  - `Costs::LLMCostCalculator` - Estimates LLM costs from call counts and token settings
  - New `costs` section in `config/settings.yml` with configurable fee rates and LLM pricing
  - Position model gains `entry_fee`, `exit_fee`, `total_fees`, `net_pnl`, `fee_breakdown` methods
  - Dashboard controller adds `cost_summary` to response
  - Positions controller adds fee info to all position responses
  - New `/api/v1/costs` endpoints: `summary`, `llm`, `trading`

### Configuration
New `costs` section in `config/settings.yml`:
```yaml
costs:
  trading:
    taker_fee_pct: 0.000450   # 0.0450%
    maker_fee_pct: 0.000150   # 0.0150%
    default_order_type: taker
  server:
    monthly_cost: 15.00
  llm:
    anthropic:
      claude-haiku-4-5:
        input_per_million: 1.00
        output_per_million: 5.00
```

### Technical Details
- No database migrations required - all calculations are done on-the-fly
- LLM costs estimated using 70% utilization factor and 3:1 input/output ratio
- Hyperliquid fees: 0.0450% taker, 0.0150% maker per transaction
- 43 new tests for cost services

## [0.20.0] - 2025-12-30

### Added
- **Hyperliquid Write Operations** - Live trading now supported via EIP-712 signed exchange operations
  - `HyperliquidClient#place_order` - Places market orders on Hyperliquid with configurable slippage
  - `HyperliquidClient#cancel_order` - Cancels orders by order ID
  - `HyperliquidClient#update_leverage` - Placeholder for leverage updates (managed at account level)
  - SDK now initialized with private key for exchange operations
  - New `exchange` accessor for write operations via gem's Exchange module
  - `validate_write_configuration!` helper to check credentials before trading

- **OrderExecutor Live Trade Handling** - Full order lifecycle management for live trades
  - Processes Hyperliquid order response (status, fill info, order ID)
  - Creates Order records with proper status transitions (pending → submitted → filled)
  - Creates/closes Position records based on fill price
  - Handles error responses from exchange

### Changed
- `HyperliquidClient` - Updated documentation to reflect write operation support
- `hyperliquid_client_spec.rb` - Updated tests for actual write operations (no longer stubs)

### Configuration
New setting `hyperliquid.slippage` in `config/settings.yml`:

### Technical Details
- Uses forked hyperliquid gem with EIP-712 signing: `github: "marcomd/hyperliquid", branch: "feature/add-eip-712-signing-and-exchange-operations"`
- Market orders use IoC (Immediate or Cancel) with slippage protection
- Stop-loss and take-profit monitoring remains local via RiskMonitoringJob (trigger orders planned for future)

### Future Enhancement
- **Trigger orders for SL/TP on exchange** - Place SL/TP as trigger orders on Hyperliquid for execution even when system is down

## [0.19.0] - 2025-12-30

### Added
- **Position Direction Evaluation Documentation** - New README section explaining how long/short decisions are made
  - Documents two-stage process: MacroStrategy sets bias, LowLevelAgent aligns decisions
  - Includes decision logic table, order mapping, PnL calculation, and SL/TP trigger rules by direction
  - Confirms both long and short positions are fully supported symmetrically

### Changed
- **Rebalanced Context Weights** - Technical indicators now primary signal instead of Prophet forecasts
  - Previous: forecast 60%, sentiment 20%, technical 15%, whale_alerts 5%
  - New: **technical 50%**, sentiment 25%, forecast 15%, whale_alerts 10%
  - Rationale: Technical indicators (EMA, RSI, MACD) are proven and based on actual price action
  - Prophet ML is better suited for business forecasting than volatile crypto markets

## [0.18.3] - 2025-12-30

### Fixed
- **RiskManager validate_risk_reward Return Type** - `validate_risk_reward` was returning a plain Hash instead of `ValidationResult` struct
  - `TradingCycleJob` crashed with `undefined method 'approved?' for an instance of Hash`
  - Changed all `{ valid: true/false, reason: "..." }` returns to `ValidationResult.new(valid: ..., reason: ...)`
  - Updated internal check from `result[:valid]` to `result.approved?` for consistency

## [0.18.2] - 2025-12-30

### Fixed
- **Forecasts Page Blank** - Fixed BigDecimal serialization in forecast API responses
  - `predicted_change_pct` returned BigDecimal which JSON serialized as string
  - Added `.to_f` conversion in `serialize_forecast` and `serialize_forecast_list` methods
  - Fixes: `forecast.change_pct.toFixed is not a function` JavaScript error

## [0.18.1] - 2025-12-30

### Removed
- **Dead code cleanup** - Removed unused `LLM::Client#provider_info` method and its test

## [0.18.0] - 2025-12-30

### Fixed
- **pg gem Segmentation Fault on macOS ARM64** - Root cause identified and fixed
  - The segfault was caused by GSSAPI/Kerberos authentication negotiation in pg gem
  - Added `gssencmode: disable` to database.yml default configuration
  - This disables GSS encryption which triggers the segfault on Apple Silicon
  - See: https://github.com/ged/ruby-pg/issues/538
- **LLM Client with_params Argument Error** - Fixed Ruby 3.4 keyword argument compatibility
  - Changed `.with_params(provider_params)` to `.with_params(**provider_params)`
  - Ruby 3.4 enforces strict separation between hash and keyword arguments
  - Fixes: "wrong number of arguments (given 1, expected 0)"
- **Solid Queue Workers Not Starting** - Restored worker process configuration
  - Changed `processes: 0` back to `processes: 1` in queue.yml
  - With gssencmode fix, forked worker processes now work correctly

### Technical Details
- The pg gem segfault was not specific to pg version (1.5.x and 1.6.x both affected)
- The root cause is macOS Keychain/GSS interaction after fork() - known Ruby ecosystem issue
- Updated queue.yml default JOB_CONCURRENCY from 0 to 1

## [0.17.1] - 2025-12-30

### Fixed
- **Gemini LLM Provider max_tokens Error** - Gemini API uses `maxOutputTokens` inside `generationConfig` instead of `max_tokens`
  - `LLM::Client#provider_params` now returns provider-specific parameter format
  - Gemini: `{ generationConfig: { maxOutputTokens: value } }`
  - Anthropic/Ollama: `{ max_tokens: value }` (unchanged)
  - Fixes error: "Invalid JSON payload received. Unknown name 'max_tokens': Cannot find field."

### Technical Details
- Added `provider_params` private method to `LLM::Client` for provider-specific token limit handling
- Updated `client_spec.rb` with separate test contexts for each provider's parameter format
- All 23 LLM client tests passing

## [0.17.0] - 2025-12-30

### Added
- **Mission Control Jobs Dashboard** - Web UI for monitoring Solid Queue background jobs
  - Mount point at `/jobs` with HTTP Basic Auth protection
  - View job queues, pending jobs, and failed jobs
  - Retry or discard failed jobs from the UI
  - `propshaft` gem for asset pipeline support in API-only mode

### Configuration
New environment variables in `.env`:
- `MISSION_CONTROL_USER` - HTTP Basic Auth username (default: admin)
- `MISSION_CONTROL_PASSWORD` - HTTP Basic Auth password (required)

## [0.16.2] - 2025-12-29

### Fixed
- **pg gem Segmentation Fault** - Pinned pg gem to version 1.5.x to avoid segfaults on macOS ARM64 with Ruby 3.4
  - pg 1.6.x has bugs that cause segfaults in `connect_start`/`connect_poll` after fork()
  - This primarily affects Solid Queue worker processes
  - pg 1.5.9 is stable and does not have these issues

### Technical Details
- Root cause: pg 1.6.x precompiled binaries segfault on macOS ARM64 (Apple Silicon) with Ruby 3.4
- The segfault occurs in libpq connection establishment after Solid Queue forks worker processes
- Even source-compiled pg 1.6.x crashed, indicating the issue is in the pg gem code itself
- Solution: Pin `gem "pg", "~> 1.5.0"` in Gemfile
- Also updated `config/queue.yml` to use `processes: 0` by default (in-process workers)

## [0.16.1] - 2025-12-29

### Fixed
- **Database Connection Health Check** - Jobs now verify database connectivity before execution
  - Added `before_perform :ensure_database_connection` callback to `ApplicationJob`
  - Checks if connection is active, reconnects if stale
  - Flushes dead connections from the pool via `connection_pool.flush!`
  - Prevents pg gem segfaults on stale/broken connections

### Added
- **Automatic Retry on Connection Errors** - Jobs now retry on database connection failures
  - `retry_on ActiveRecord::ConnectionNotEstablished` (3 attempts, 5s wait)
  - `retry_on PG::ConnectionBad` (3 attempts, 5s wait)
- **ApplicationJob Tests** - New spec file `spec/jobs/application_job_spec.rb`
  - Tests for active connection, stale connection reconnect, connection failure handling
  - Tests for retry configuration

### Technical Details
- Root cause: pg gem segfaults on stale connections instead of raising proper exceptions
- Solution: Proactively check and reconnect before job execution
- All 5 jobs (TradingCycle, MarketSnapshot, Forecast, MacroStrategy, RiskMonitoring) now inherit this protection

## [0.16.0] - 2025-12-29

### Added
- **LLM Model Tracking** - Track which LLM model made each decision for debugging and performance analysis
  - `llm_model` column added to `trading_decisions` table
  - `llm_model` column added to `macro_strategies` table
  - `Reasoning::LowLevelAgent` now stores `llm_model` when creating decisions
  - `Reasoning::HighLevelAgent` now stores `llm_model` when creating macro strategies
  - API controllers serialize `llm_model` in responses (decisions, macro_strategies, dashboard)

### Technical Details
- 1 new database migration (add_llm_model_to_decisions_and_strategies)
- 6 new test examples for llm_model storage and serialization
- All 556 examples passing, RuboCop clean

### Support Frontend (0.5.0)

## [0.15.2] - 2025-12-29

### Fixed
- **Excessive sync_account Execution Logs** - Removed success logging from `AccountManager.fetch_account_state`
  - Read operations no longer create ExecutionLog records (they are not execution events)
  - Failure logging preserved to track API errors
  - Fixes dashboard showing many "Sync Account" entries from frequent dashboard refreshes and RiskMonitoringJob runs
- **LLM::Client Tests Environment Independence** - Tests now stub `Settings.llm.provider` to `anthropic`
  - Tests no longer fail when `LLM_PROVIDER` environment variable is set to a different provider

## [0.15.1] - 2025-12-29

### Fixed
- **Docker Multi-Database Setup** - `docker-compose.yml` was only creating one database
  - Added `docker/init-db.sql` initialization script that creates all required databases
  - Creates development databases: `hypersense_development`, `_cache`, `_queue`, `_cable`
  - Creates test databases: `hypersense_test`, `_cache`, `_queue`, `_cable`
  - Grants privileges to `hypersense` user on all databases

### Changed
- `docker-compose.yml` now mounts init script to `/docker-entrypoint-initdb.d/`

### Migration Notes
If you have an existing PostgreSQL volume, you must recreate it for the init script to run:
```bash
docker compose down -v   # WARNING: Deletes all data
docker compose up -d
rails db:create db:migrate
```

## [0.15.0] - 2025-12-28

### Added
- **Execution Logs Dashboard** - New page to view and filter execution logs
  - `Api::V1::ExecutionLogsController` - REST API with index, show, stats endpoints
  - Filters: status (success/failure), log_action (place_order, cancel_order, etc.), date range
  - Pagination support with meta information
  - Statistics endpoint showing success rate and action breakdown

### Support Frontend (0.4.0)

### Technical Details
- 11 new request spec examples for ExecutionLogsController
- Used `log_action` parameter instead of `action` (reserved Rails param)
- All tests passing, RuboCop and ESLint clean

## [0.14.0] - 2025-12-28

### Added
- **LLM-Agnostic Architecture** - Replaced single-provider Anthropic integration with multi-provider support
  - `LLM::Client` - Unified LLM client wrapper using ruby_llm gem
  - `LLM::Error`, `LLM::RateLimitError`, `LLM::APIError`, `LLM::ConfigurationError`, `LLM::InvalidResponseError` - Custom error hierarchy
  - Support for Anthropic, Google Gemini, and Ollama providers via `LLM_PROVIDER` env var
  - Per-provider model configuration: `ANTHROPIC_MODEL`, `GEMINI_MODEL`, `OLLAMA_MODEL`

### Changed
- Replaced `anthropic` gem with `ruby_llm` gem in Gemfile
- `Reasoning::HighLevelAgent` now uses `LLM::Client` instead of `Anthropic::Client`
- `Reasoning::LowLevelAgent` now uses `LLM::Client` instead of `Anthropic::Client`
- Updated `config/settings.yml` with multi-provider LLM configuration
- Updated error handling from Anthropic-specific to generic `LLM::` error classes

### Configuration
New LLM settings in `config/settings.yml`:
```yaml
llm:
  provider: <%= ENV.fetch('LLM_PROVIDER', 'anthropic') %>
  anthropic:
    api_key: <%= ENV.fetch('ANTHROPIC_API_KEY', '') %>
    model: <%= ENV.fetch('ANTHROPIC_MODEL', 'claude-sonnet-4-5') %>
  gemini:
    api_key: <%= ENV.fetch('GEMINI_API_KEY', '') %>
    model: <%= ENV.fetch('GEMINI_MODEL', 'gemini-2.0-flash-exp') %>
  ollama:
    api_base: <%= ENV.fetch('OLLAMA_API_BASE', 'http://localhost:11434/v1') %>
    model: <%= ENV.fetch('OLLAMA_MODEL', 'llama3') %>
```

### Technical Details
- New files: `app/services/llm/client.rb`, `app/services/llm/errors.rb`, `config/initializers/ruby_llm.rb`
- ruby_llm handles automatic retry with backoff for rate limits
- Provider switch requires only changing `LLM_PROVIDER` env var and setting provider-specific credentials
- No changes to LLM prompt structure or decision parsing

## [0.13.4] - 2025-12-28

### Changed
- **Database Configuration via Environment Variables** - Moved database settings from hardcoded values to `.env` file
  - `DATABASE_URL` (and `_CACHE_URL`, `_QUEUE_URL`, `_CABLE_URL`) takes priority when set for remote databases
  - Individual env vars (`DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_DATABASE`) as fallback
  - Default port changed to `5433` to match docker-compose configuration
  - Production requires env vars (no hardcoded defaults for security)

### Updated
- `config/database.yml` - Now uses ERB with `ENV.fetch` and sensible defaults
- `.env.example` - Added database configuration section with documented options
- `README.md` - Updated setup instructions with database configuration details

### Technical Details
- Multi-database setup preserved (primary, cache, queue, cable)
- Test environment uses `DATABASE_TEST_*` vars or defaults with `_test` suffix
- Seamless migration: existing Docker setups work without changes

## [0.13.3] - 2025-12-28

### Fixed
- **PositionManager Nil Crash** - `sync_from_hyperliquid` was crashing with `NoMethodError: undefined method 'to_d' for nil`
  - Added nil validation for `entryPx` field before processing positions
  - Added nil check for `coin` (symbol) field
  - Added safe navigation (`&.`) for `szi` (size) field
  - Positions with missing required data are now skipped with a warning log

- **OrderExecutor Price Fetch Crash** - `validate_decision` was crashing when price fetch failed
  - Wrapped `fetch_current_price` in error handling during validation
  - Returns graceful rejection instead of crashing the job

- **TradingCycle Error Handling** - `sync_positions_if_configured` only caught `HyperliquidApiError`
  - Now catches all `StandardError` to prevent `NoMethodError` from crashing the cycle
  - Logs error class name for better debugging

### Added
- **Regression Tests** - Specs to prevent these issues from recurring
  - `position_manager_spec.rb` - 4 new examples for nil handling (missing entryPx, missing coin, nil size)
  - `order_executor_spec.rb` - 2 new examples for price fetch failure handling

### Technical Details
- Root cause: Inconsistent use of safe navigation operators (`&.`) in PositionManager
- Line 52 had `pos_data["entryPx"].to_d` while lines 53, 55, 56 correctly used `&.to_d`
- Crash occurred every 5 minutes when TradingCycleJob called `sync_positions_if_configured`

## [0.13.2] - 2025-12-28

### Added
- **Missing Job Specs** - Complete test coverage for all background jobs
  - `spec/jobs/forecast_job_spec.rb` - 9 examples covering forecast generation, validation, error handling
  - `spec/jobs/macro_strategy_job_spec.rb` - 8 examples covering strategy creation, ActionCable broadcast
  - `spec/jobs/market_snapshot_job_spec.rb` - 10 examples covering data fetching, indicator calculation, broadcasts
  - `spec/jobs/trading_cycle_job_spec.rb` - 8 examples covering cycle execution, decision broadcasting

### Changed
- **Extracted Magic Numbers to Constants** - Improved code maintainability

  **Models:**
  - `MarketSnapshot::RSI_OVERSOLD_THRESHOLD` = 30, `RSI_OVERBOUGHT_THRESHOLD` = 70
  - `Forecast::BEARISH_THRESHOLD_PCT` = -0.5, `BULLISH_THRESHOLD_PCT` = 0.5

  **Controllers:**
  - `DashboardController::RECENT_POSITIONS_LIMIT` = 10
  - `DashboardController::RECENT_DECISIONS_LIMIT` = 5
  - `DashboardController::REASONING_TRUNCATE_LENGTH` = 100
  - `DashboardController::MARKET_DATA_HEALTH_MINUTES` = 5
  - `DashboardController::TRADING_CYCLE_HEALTH_MINUTES` = 15

  **Services:**
  - `Risk::PositionSizer::BTC_DECIMAL_PRECISION` = 8, `USD_DECIMAL_PRECISION` = 2
  - `Risk::CircuitBreaker::DEFAULT_MAX_DAILY_LOSS` = 0.05
  - `Risk::CircuitBreaker::DEFAULT_MAX_CONSECUTIVE_LOSSES` = 3
  - `Risk::CircuitBreaker::DEFAULT_COOLDOWN_HOURS` = 24
  - `Risk::RiskManager::DEFAULT_MIN_RISK_REWARD_RATIO` = 2.0
  - `Reasoning::LowLevelAgent::RECENT_NEWS_LIMIT` = 5, `WHALE_ALERTS_LIMIT` = 5
  - `Reasoning::ContextAssembler::PRICE_ACTION_CANDLES_LIMIT` = 24

### Technical Details
- All 113 files pass RuboCop (Omakase Ruby style)
- 515 examples, 0 failures (35 new job spec examples)
- No breaking changes to public APIs

## [0.13.1] - 2025-12-28

### Fixed
- **Code Documentation** - Added comprehensive YARD-style documentation with `@return` types and examples
  - `TradingCycle` - All public and private methods now documented
  - `Indicators::Calculator` - All indicator methods include examples and return types
  - `DashboardController` - All private helper methods documented
  - `MarketSnapshot` - Instance methods for indicators documented with examples
  - `MarketSnapshotJob` - Private methods documented

- **N+1 Query in DashboardController** - `market_overview` method optimized
  - Changed from N individual queries to 2 batch queries using `latest_per_symbol` and `DISTINCT ON`
  - Now uses `index_by(&:symbol)` for O(1) lookup instead of N queries

- **SQL Injection Risk in PricePredictor** - `fetch_price_at` method refactored
  - Removed raw SQL with string interpolation (`Arel.sql("ABS(EXTRACT(EPOCH FROM ...))"`)
  - Now uses parameterized range query with in-memory sorting for closest match
  - Safer approach without performance impact (typically 0-4 records in result set)

### Technical Details
- All 6 modified files pass RuboCop (Omakase Ruby style)
- No breaking changes to public APIs
- Documentation follows CLAUDE.md guidelines (`@return [Type]` with examples)

## [0.13.0] - 2025-12-28

### Fixed
- **Prophet DataFrame Format** - ForecastJob was failing with "Must be a data frame" error
  - Changed from array of hashes to `Rover::DataFrame` for Prophet input data
  - Added `require "rover"` to `Forecasting::PricePredictor`
  - Fixed frequency parameter from `"T"` to `"60S"` (prophet-rb doesn't support pandas-style "T")
  - Fixed value extraction from `prediction.last["yhat"]` to `prediction["yhat"].last` (returns Float instead of Rover::Vector)

- **TradingDecision String Division Error** - TradingCycleJob was failing with "undefined method '/' for String"
  - LLM JSON responses can return numeric values as strings (e.g., `"leverage": "5"`)
  - Added `.to_i` / `.to_f` conversions to accessor methods: `leverage`, `target_position`, `stop_loss`, `take_profit`

### Added
- **Regression Tests** - Specs to prevent these issues from recurring
  - `spec/services/forecasting/price_predictor_spec.rb` - 10 examples covering DataFrame format, value extraction, frequency strings
  - `spec/models/trading_decision_spec.rb` - Added 5 examples for string-to-numeric conversion from LLM JSON

### Technical Details
- Prophet-rb valid frequencies: `"60S"` (seconds), `"H"` (hours), `"D"` (days), `"W"` (weeks), `"MS"` (month start)
- Forecasts now generating: 8 forecasts per cycle (1m and 15m for BTC, ETH, SOL, BNB)
- All 46 new tests passing, 163 total model tests, RuboCop clean

## [0.12.0] - 2025-12-28

### Added
- **Position Awareness for LLM Trading Agent** - The LLM now receives information about existing positions when making trading decisions
  - `ContextAssembler#current_position_for` - Returns position data (direction, size, entry_price, current_price, unrealized_pnl, leverage, stop_loss, take_profit) or `has_position: false`
  - `LowLevelAgent#format_position` - Formats position status for the LLM prompt
  - **CLOSE operation** - LLM can now decide to close existing positions based on market conditions

### Changed
- `Reasoning::ContextAssembler` now includes `current_position` in trading context
- `Reasoning::LowLevelAgent` system prompt updated with:
  - **Position Awareness** section explaining available operations based on position state
  - **Decision logic** for open/close/hold based on position existence
  - **CLOSE action** output JSON schema
  - Updated **Rules** clarifying position-aware operation constraints
- User prompt now includes `## Current Position Status` section before market data

### Fixed
- **Phantom Position Bug** - When trades failed to execute (e.g., insufficient margin), the LLM would incorrectly say "hold" on non-existent positions. Now the LLM explicitly sees whether a position exists and can decide to open if market conditions warrant.

### Technical Details
- 20 new tests across `context_assembler_spec.rb` and `low_level_agent_spec.rb`
- 254 service tests passing, RuboCop clean
- No changes to `OrderExecutor` or `DecisionParser` (already support "close" operation)

## [0.11.0] - 2025-12-28

### Fixed
- **Credential Configuration Bug** - Trading decisions were not being executed due to credential mismatch
  - `HyperliquidClient` was reading from `Rails.application.credentials` (nil) instead of ENV variables
  - Updated `private_key` and `wallet_address` methods to use `ENV.fetch("HYPERLIQUID_PRIVATE_KEY", nil)` and `ENV.fetch("HYPERLIQUID_ADDRESS", nil)`
  - Error messages now reference `.env` file instead of Rails credentials

### Added
- `AccountManager#ensure_configured!` - Pre-flight check before trading operations
  - Raises `ConfigurationError` with clear setup instructions when credentials missing
  - Called at the start of `can_trade?` to fail fast with actionable error message

### Technical Details
- Updated `hyperliquid_client_spec.rb` tests to mock ENV instead of Rails credentials
- Added 2 new tests in `account_manager_spec.rb` for missing credentials scenario
- All 32 execution service tests passing, RuboCop clean

## [0.10.0] - 2025-12-27

### Changed
- Improved the prompt for making both low and high agents to work with clearer instructions and added psychological pressure

## [0.9.0] - 2025-12-26

### Added
- **Market Data List Endpoints** - New paginated API endpoints for frontend detail pages
  - `GET /api/v1/market_data/snapshots` - Paginated market snapshots with filters (symbol, date range)
  - `GET /api/v1/market_data/forecasts?page=1` - Paginated forecasts list format (vs aggregated for dashboard)
  - `serialize_snapshot_list` - Snapshot serializer for list views with RSI/MACD signals
  - `serialize_forecast_list` - Forecast serializer for list views with id, symbol, timeframe
  - `render_forecasts_list` - Private method for paginated forecast list rendering

### Changed
- `MarketDataController#forecasts` now supports dual formats:
  - Without pagination params: Returns aggregated format grouped by symbol/timeframe (dashboard)
  - With pagination params (`page`, `per_page`): Returns paginated list format (detail pages)

### Technical Details
- 1 new factory: `spec/factories/forecasts.rb`
- 1 new request spec: `spec/requests/api/v1/market_data_spec.rb` (12 examples)
- Filters supported: `symbol`, `timeframe`, `start_date`, `end_date`, `page`, `per_page`

## [0.8.0] - 2025-12-26

### Added
- **REST API Controllers** - Full API layer for React dashboard
  - `Api::V1::DashboardController` - Aggregated dashboard data (account, positions, market, strategy)
  - `Api::V1::PositionsController` - Positions CRUD with open/performance endpoints
  - `Api::V1::DecisionsController` - Trading decisions with recent/stats endpoints
  - `Api::V1::MarketDataController` - Current prices, history, forecasts per symbol
  - `Api::V1::MacroStrategiesController` - Strategy history with current endpoint
  - `Api::V1::HealthController` - Health check with version info
  - `Api::V1::BaseController` - Shared error handling and JSON responses

- **ActionCable WebSocket Channels** - Real-time updates for dashboard
  - `DashboardChannel` - Broadcasts market, position, decision, strategy updates
  - `MarketsChannel` - Per-symbol price ticker subscriptions
  - Connection authentication and channel authorization

- **Background Job Broadcasts** - Jobs now broadcast updates via ActionCable
  - `MarketSnapshotJob` - Broadcasts to DashboardChannel and MarketsChannel
  - `TradingCycleJob` - Broadcasts decision updates
  - `MacroStrategyJob` - Broadcasts strategy updates

### Changed
- Updated `config/routes.rb` with full API v1 namespace
- Updated `config/database.yml` for ActionCable cable database
- Added CORS configuration for React frontend

### Technical Details
- 3 new request specs (dashboard, health, positions)
- ActionCable mounted at `/cable`
- JSON API responses with pagination meta

## [0.7.0] - 2024-12-25

### Added
- **Predictive Modeling & Weighted Context** (Phase 5.1 complete)
  - `Forecast` model - Price predictions with MAE/MAPE accuracy tracking
  - `Forecasting::PricePredictor` - Prophet-based ML forecasting for 1m, 15m, 1h timeframes
  - `ForecastJob` - Background job (every 5 min) for automated price predictions
  - `DataIngestion::NewsFetcher` - RSS news from coinjournal.net with asset filtering
  - `DataIngestion::WhaleAlertFetcher` - Large transfer monitoring from whale-alert.io
  - Weighted context system for LLM reasoning (forecast: 0.6, sentiment: 0.2, technical: 0.1, whale_alerts: 0.1)

### Changed
- `Reasoning::ContextAssembler` now includes:
  - `context_weights` from Settings.weights
  - `forecast` data from Prophet predictions
  - `news` from RSS feed
  - `whale_alerts` from whale-alert.io
- `Reasoning::LowLevelAgent` system prompt updated with weight instructions
- `Reasoning::HighLevelAgent` system prompt updated with weight instructions
- User prompts reorganized by weight priority with clear section headers
- Updated `config/recurring.yml` with ForecastJob schedule

### Technical Details
- Added `prophet-rb` gem for time series forecasting
- 1 new database migration (create_forecasts)
- 3 new data services with caching (NewsFetcher: 5min, WhaleAlertFetcher: 2min)
- Test stubs for external services (spec/support/external_services_stubs.rb)
- 417 total tests, all passing

### Configuration
Context weights in `config/settings.yml`:
```yaml
weights:
  forecast: 0.6      # Prophet ML predictions (PRIMARY signal)
  sentiment: 0.2     # Fear & Greed + News
  technical: 0.1     # EMA, RSI, MACD, Pivots
  whale_alerts: 0.1  # Large capital movements
```

### Data Sources
- **Forecasting**: Prophet ML model trained on MarketSnapshot historical data
- **News**: RSS from https://coinjournal.net/news/feed (no API key required)
- **Whale Alerts**: JSON from https://whale-alert.io/data.json (no API key required)

## [0.6.0] - 2024-12-23

### Added
- **Risk Management System** (Phase 5 complete)
  - `Risk::RiskManager` - Centralized risk validation (confidence, leverage, margin, R/R ratio)
  - `Risk::PositionSizer` - Risk-based position sizing using formula: `size = (account_value * max_risk_pct) / risk_per_unit`
  - `Risk::StopLossManager` - SL/TP enforcement with market order execution on trigger
  - `Risk::CircuitBreaker` - Trading halt on excessive losses (daily loss limit, consecutive losses, cooldown)
  - `RiskMonitoringJob` - Background job (every minute) for SL/TP monitoring and circuit breaker updates
  - Position risk fields: `stop_loss_price`, `take_profit_price`, `risk_amount`, `realized_pnl`, `close_reason`
  - Position helper methods: `stop_loss_triggered?`, `take_profit_triggered?`, `risk_reward_ratio`, distance calculations

### Changed
- `TradingCycle` now integrates all risk services:
  - Checks circuit breaker before allowing trades
  - Uses `Risk::RiskManager.validate` for centralized decision validation
  - Uses `Risk::PositionSizer` for optimal position sizing
- `Execution::OrderExecutor` now passes SL/TP to positions and calculates risk amount
- `Execution::PositionManager.open_position` accepts `stop_loss_price`, `take_profit_price`, `risk_amount`
- `ExecutionLog` now supports `risk_trigger` action for SL/TP events
- Updated `config/settings.yml` with new risk parameters
- Updated `config/recurring.yml` with `risk_monitoring` job schedule

### Fixed
- `Execution::HyperliquidClient` updated to use new gem API (`Hyperliquid::SDK` with `sdk.info.*` methods)
- Fixed hyperliquid_client_spec.rb to properly mock `Hyperliquid::SDK` and `Hyperliquid::Info`

### Configuration
New risk settings in `config/settings.yml`:
```yaml
risk:
  max_risk_per_trade: 0.01         # 1% of capital per trade
  min_risk_reward_ratio: 2.0       # Minimum R/R ratio (2:1)
  enforce_risk_reward_ratio: true  # Reject below min R/R (false = warn only)
  max_daily_loss: 0.05             # 5% max daily loss (circuit breaker)
  max_consecutive_losses: 3        # Consecutive losses before halt
  circuit_breaker_cooldown: 24     # Hours to wait after trigger
```

### Technical Details
- 1 new database migration (add_risk_fields_to_positions)
- 4 new risk services with full test coverage
- 1 new background job (RiskMonitoringJob)
- Circuit breaker uses `Rails.cache` for state persistence (can migrate to DB later)
- SL/TP orders execute as market orders for guaranteed fills
- Risk/reward validation configurable: enforce (reject) or warn-only mode
- 417 total tests, all passing

## [0.5.1] - 2024-12-23

### Changed
- Move Anthropic API setting from rails credentials to settings.yml
  - config/settings.yml reads them via ERB: <%= ENV.fetch('ANTHROPIC_API_KEY', '') %>
  - Code accesses via Settings.anthropic.api_key

## [0.5.0] - 2024-12-23

### Added
- **Hyperliquid Integration** (Phase 4 complete)
  - `Position` model - Tracks open/closed positions with PnL calculations
  - `Order` model - Exchange orders with full lifecycle (pending → submitted → filled/cancelled/failed)
  - `ExecutionLog` model - Audit trail for all execution operations
  - `Execution::HyperliquidClient` - Exchange API wrapper with read operations
  - `Execution::AccountManager` - Account state, margin calculations, trading eligibility
  - `Execution::PositionManager` - Position sync from Hyperliquid, price updates
  - `Execution::OrderExecutor` - Order execution with paper trading simulation
  - Paper trading mode enabled by default (`Settings.trading.paper_trading: true`)
  - Hyperliquid gem branch with EIP-712 signing and exchange write operations

### Changed
- `TradingCycle` now integrates full execution pipeline:
  - Syncs positions from Hyperliquid on each cycle
  - Filters and approves decisions based on confidence and position limits
  - Executes approved trades (paper or live mode)
- Updated `config/settings.yml` with Hyperliquid configuration (testnet/mainnet URLs, timeouts)
- Hyperliquid gem now uses `feature/add-eip-712-signing-and-exchange-operations` branch

### Technical Details
- 3 new database migrations (positions, orders, execution_logs)
- 4 new execution services with full test coverage
- Position tracking with unrealized PnL, liquidation price, margin used
- Order lifecycle management with Hyperliquid order ID tracking
- `ActiveSupport::Testing::TimeHelpers` added to RSpec for `freeze_time` support

### Documentation
- `docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md` - Detailed spec for gem write operations
- Updated README.md with execution layer usage examples

## [0.4.0] - 2024-12-23

### Added
- `dotenv-rails` gem for environment variable management
- `.env.example` template file for required environment variables

### Changed
- LLM model configuration (`LLM_MODEL`) now loaded from `.env` file via `settings.yml` ERB
- Updated setup instructions in README.md to include environment variable configuration

## [0.3.0] - 2024-12-21

### Added
- **Multi-Agent Reasoning Engine** (Phase 3 complete)
  - `MacroStrategy` model - Daily macro analysis with bias, risk tolerance, key support/resistance levels
  - `TradingDecision` model - Per-asset trading decisions with operation, direction, confidence, stops
  - `Reasoning::ContextAssembler` - Assembles market data, indicators, and sentiment for LLM prompts
  - `Reasoning::DecisionParser` - JSON schema validation using dry-validation contracts
  - `Reasoning::HighLevelAgent` - Daily macro strategist (runs at 6am via `MacroStrategyJob`)
  - `Reasoning::LowLevelAgent` - Trade executor for each asset (runs every 5 min via `TradingCycleJob`)
  - `TradingCycle` orchestrator - Ensures macro strategy freshness, runs low-level agent for all assets

### Changed
- `MacroStrategyJob` now calls `Reasoning::HighLevelAgent.new.analyze`
- `TradingCycleJob` now calls `TradingCycle.new.execute`
- LLM configuration (model, max_tokens, temperature) moved to `config/settings.yml`

### Technical Details
- Claude model: `claude-sonnet-4-20250514` (configurable via `Settings.llm.model`)
- Validation schemas: dry-validation contracts with conditional rules
- Error handling: Fallback to neutral/hold decisions on API errors or invalid responses
- Test coverage: 155 examples across 6 new spec files

## [0.2.0] - 2024-12-21

### Added
- **Data Pipeline** (Phase 2 complete)
  - `DataIngestion::PriceFetcher` - Binance API integration for BTC, ETH, SOL, BNB
  - `DataIngestion::SentimentFetcher` - Fear & Greed Index with interpretation
  - `Indicators::Calculator` - EMA, RSI, MACD, Pivot Points
  - `MarketSnapshot` model with JSONB indicators storage
  - `MarketSnapshotJob` - Captures market data every minute
- Hyperliquid gem integration (forked: github.com/marcomd/hyperliquid)

## [0.1.0] - 2024-12-21

### Added
- **Foundation** (Phase 1 complete)
  - Rails 8.1 API-only application
  - PostgreSQL 16 via Docker (port 5433)
  - Solid Queue for background jobs (no Redis)
  - Service architecture (`data_ingestion/`, `indicators/`, `reasoning/`, `execution/`, `risk/`)
  - Job stubs: `TradingCycleJob`, `MacroStrategyJob`, `MarketSnapshotJob`
  - Configuration via `config/settings.yml`
  - RSpec + VCR testing setup
  - CORS configured for React frontend
