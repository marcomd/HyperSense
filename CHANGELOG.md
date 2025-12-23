# Changelog

All notable changes to HyperSense.

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
