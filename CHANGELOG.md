# Changelog

All notable changes to HyperSense.

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
