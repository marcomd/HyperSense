# Changelog

All notable changes to HyperSense.

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
