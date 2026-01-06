# HyperSense

**Version 0.37.1** | Autonomous AI Trading Agent for cryptocurrency markets.

![HyperSense_cover1.jpg](docs/HyperSense_cover1.jpg)

## Overview

HyperSense is an autonomous trading agent that operates in discrete cycles to analyze market data and execute trades on decentralized exchanges (DEX). It uses Claude AI for reasoning and decision-making.

**note**: this is the backend, go here for the [HyperSense Dashboard](https://github.com/marcomd/HyperSenseDashboard/)

### Key Features

- **Autonomous Operation**: Dynamic scheduling based on market volatility (3-25 minutes)
- **Multi-Agent Architecture**: High-level (macro strategy) + Low-level (trade execution) agents
- **Technical Analysis**: EMA, RSI, MACD, ATR (volatility), Pivot Points
- **Risk Profiles**: User-selectable trading styles (Cautious/Moderate/Fearless) with different parameters
- **Risk Management**: Position sizing, stop-loss, take-profit, confidence scoring
- **Cost Tracking**: On-the-fly calculation of trading fees, LLM costs, and server costs with net P&L
- **Real-time Dashboard**: React frontend with routing, filters, and detail pages

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         1. DATA INGESTION LAYER                             │
│                    (MarketSnapshotJob - runs every minute)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  EXTERNAL DATA SOURCES:                                                     │
│  ├─ Binance API ────────► Prices, 24h stats, 250 hourly candles             │
│  ├─ Alternative.me ─────► Fear & Greed Index (market sentiment)             │
│  ├─ CoinJournal RSS ────► Crypto news headlines                             │
│  └─ Whale-Alert.io ─────► Large capital movements ($10M+ transfers)         │
│                                                                             │
│  CALCULATED INDICATORS:                                                     │
│  └─ Indicators::Calculator ─► EMA, RSI, MACD, ATR, Pivot Points             │
│                                                                             │
│  OUTPUT: MarketSnapshot (PostgreSQL) ─► Historical archive for analysis     │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
┌───────────────────────────────┐   ┌───────────────────────────────────────┐
│  2. HIGH-LEVEL AGENT          │   │  3. USER SETTINGS                     │
│  (MacroStrategyJob - daily)   │   │  (Dashboard Risk Profile Selector)    │
├───────────────────────────────┤   ├───────────────────────────────────────┤
│                               │   │  Profiles: Cautious/Moderate/Fearless │
│  INPUTS (weighted):           │   │                                       │
│  ├─ Technical (50%)           │   │  Controls:                            │
│  ├─ Sentiment (25%)           │   │  ├─ RSI thresholds (entry signals)    │
│  ├─ Forecast (15%)            │   │  ├─ Min confidence required           │
│  └─ Whale alerts (10%)        │   │  ├─ Default leverage                  │
│                               │   │  └─ Max open positions                │
│  OUTPUT: MacroStrategy        │   │                                       │
│  ├─ Market bias (bull/bear)   │   │  Like a captain adjusting the rudder  │
│  ├─ Risk tolerance (0-1)      │   │  to steer the trading ship            │
│  └─ Support/resistance levels │   │                                       │
└───────────────────────────────┘   └───────────────────────────────────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         4. LOW-LEVEL AGENT                                  │
│                 (TradingCycleJob - every 3-25 minutes)                      │
├─────────────────────────────────────────────────────────────────────────────┤
│  INPUTS:                                                                    │
│  ├─ MarketSnapshot data (prices, indicators, sentiment, news, whale alerts) │
│  ├─ MacroStrategy (daily bias and risk tolerance)                           │
│  ├─ Risk Profile settings (thresholds and limits)                           │
│  └─ Current position status (if any)                                        │
│                                                                             │
│  OUTPUT: TradingDecision for each asset (BTC, ETH, SOL, BNB)                │
│  ├─ Operation: OPEN / CLOSE / HOLD                                          │
│  ├─ Direction: Long (buy) / Short (sell)                                    │
│  ├─ Entry price, Stop-loss, Take-profit levels                              │
│  ├─ Position size and leverage                                              │
│  └─ Confidence score and reasoning                                          │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         5. RISK MANAGEMENT LAYER                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  VALIDATION (RiskManager):                                                  │
│  ├─ Confidence meets minimum threshold                                      │
│  ├─ Position size within limits                                             │
│  ├─ Leverage within allowed range                                           │
│  └─ Risk/reward ratio acceptable                                            │
│                                                                             │
│  MONITORING (RiskMonitoringJob - every minute):                             │
│  ├─ Check stop-loss triggers → Auto-close losing positions                  │
│  ├─ Check take-profit triggers → Auto-close winning positions               │
│  └─ Circuit breaker → Halt trading if daily loss exceeds 5%                 │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         6. EXECUTION LAYER                                  │
│                    (OrderExecutor → Hyperliquid DEX)                        │
├─────────────────────────────────────────────────────────────────────────────┤
│  WALLET MANAGEMENT:                                                         │
│  └─ HyperSense has FULL CONTROL of the connected crypto wallet              │
│     ├─ Opens positions (buys/sells)                                         │
│     ├─ Closes positions (realizes profit/loss)                              │
│     ├─ Sets leverage per trade                                              │
│     └─ All operations cryptographically signed (EIP-712)                    │
│                                                                             │
│  MODES:                                                                     │
│  ├─ Paper Trading: Simulated execution (no real funds at risk)              │
│  └─ Live Trading: Real orders on Hyperliquid exchange                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

## How It Works

### 1. Data Collection (Every Minute)

**MarketSnapshotJob** runs every minute and collects data from multiple sources:

| Source | Data Collected | Purpose |
|--------|----------------|---------|
| Binance API | Prices, 24h stats, 250 hourly candles | Price data and historical analysis |
| Alternative.me | Fear & Greed Index (0-100) | Market sentiment |
| CoinJournal RSS | Crypto news headlines | News sentiment |
| Whale-Alert.io | Large transfers ($10M+) | Smart money movements |

All data is stored in **MarketSnapshot** records (PostgreSQL) for historical analysis and fed to the AI agents.

### 2. Technical Indicators

The **Indicators::Calculator** computes 5 indicators from the 250 hourly candles:

| Indicator | What It Measures | Trading Signals |
|-----------|------------------|-----------------|
| **EMA** (20/50/100/200) | Trend direction | Price above EMA = bullish, below = bearish |
| **RSI** (14-period) | Momentum (0-100 scale) | Below 30 = oversold (buy signal), Above 70 = overbought (sell signal) |
| **MACD** | Trend-following momentum | Positive histogram = bullish, Negative = bearish |
| **ATR** (14-period) | Volatility | Controls trading frequency: high volatility = more frequent trades |
| **Pivot Points** | Support/Resistance levels | Entry and exit price targets (PP, R1, R2, S1, S2) |

### 3. External Data Sources

**Fear & Greed Index** (0-100): A contrarian indicator. Extreme fear (0-24) often signals buying opportunities, while extreme greed (75-100) may signal caution.

**News Headlines**: Recent crypto news from RSS feeds. The AI agents consider headlines when making decisions.

**Whale Alerts**: Large capital movements ($10M+) can signal smart money positioning:
- Stablecoin minted → Potentially bullish (buying power entering)
- Transfer to exchange → Potentially bearish (selling pressure)
- Transfer from exchange → Potentially bullish (accumulation)

### 4. The Two-Agent System

HyperSense uses two AI agents working together:

**High-Level Agent** (runs daily at 6am):
- Analyzes overall market conditions
- Sets the daily bias: **bullish**, **bearish**, or **neutral**
- Defines risk tolerance (0.0 = conservative, 1.0 = aggressive)
- Identifies key support/resistance levels for each asset

**Low-Level Agent** (runs every 3-25 minutes):
- Receives the daily macro strategy as context
- Makes specific trading decisions for each asset (BTC, ETH, SOL, BNB)
- Can override macro bias when technical signals are strong
- Outputs: operation (open/close/hold), direction, leverage, stop-loss, take-profit

**Weighted Inputs**: Both agents prioritize data by weight:
- Technical indicators: **50%** (primary signal)
- Sentiment: **25%** (Fear & Greed, news)
- Forecasts: **15%** (Prophet ML predictions)
- Whale alerts: **10%** (smart money hints)

### 5. Risk Profiles (User Settings)

Users can select a risk profile from the dashboard to adjust trading behavior:

| Parameter | Cautious | Moderate | Fearless |
|-----------|----------|----------|----------|
| RSI Oversold | 35 | 30 | 25 |
| RSI Overbought | 65 | 70 | 75 |
| Min Confidence | 70% | 60% | 50% |
| Default Leverage | 2x | 3x | 5x |
| Max Positions | 3 | 5 | 7 |

**Like a captain adjusting the rudder** to steer the ship: the risk profile controls how aggressively the trading agent pursues opportunities. Cautious profiles require stronger signals and use lower leverage; Fearless profiles act on weaker signals with higher leverage.

### 6. Trade Execution & Wallet Management

**HyperSense has full control of the connected crypto wallet**. When a trading decision is approved:

1. **RiskManager validates** the decision (confidence, position size, leverage limits)
2. **OrderExecutor** creates the order and sends it to Hyperliquid
3. **Orders are cryptographically signed** using EIP-712 (wallet private key)
4. **Position is created/updated** with entry price, stop-loss, take-profit

**Two operating modes:**
- **Paper Trading**: Simulated execution (no real funds at risk) - perfect for testing
- **Live Trading**: Real orders on Hyperliquid exchange

**Continuous monitoring** (RiskMonitoringJob every minute):
- Auto-closes positions when stop-loss or take-profit is triggered
- Circuit breaker halts all trading if daily loss exceeds 5%

### Job Schedule Summary

| Frequency | Job | Purpose |
|-----------|-----|---------|
| Every minute | MarketSnapshotJob | Collect prices, indicators, sentiment |
| Every minute | RiskMonitoringJob | Monitor SL/TP, circuit breaker |
| Dynamic (3-25 min) | TradingCycleJob | Main trading orchestration |
| Daily (6am) | MacroStrategyJob | High-level market analysis |
| Every 30 min | BootstrapTradingCycleJob | Safety net to restart trading |

**Dynamic Scheduling**: Trading frequency adapts to volatility:
- Very High volatility (ATR ≥ 3%): every 3 min
- High volatility (ATR ≥ 2%): every 6 min
- Medium volatility (ATR ≥ 1%): every 12 min
- Low volatility (ATR < 1%): every 25 min

### Background Jobs Dashboard

HyperSense includes Mission Control Jobs for monitoring Solid Queue:

**Access:** http://localhost:3000/jobs

**Authentication:** HTTP Basic Auth (configure in `.env`)

```bash
MISSION_CONTROL_USER=admin
MISSION_CONTROL_PASSWORD=your_secure_password
```

## Tech Stack

| Component | Technology | Notes |
|-----------|------------|-------|
| Framework | Rails 8.1 API | Latest version |
| Database | PostgreSQL 16 | Port 5433 (avoids local PG conflict) |
| Job Queue | Solid Queue | No Redis needed! |
| Job Dashboard | Mission Control Jobs | Web UI for Solid Queue |
| Scheduling | recurring.yml | Built into Solid Queue |
| LLM | ruby_llm gem | Multi-provider (Anthropic, Gemini, Ollama, OpenAI) |
| Exchange | hyperliquid gem (forked) | Extend with write ops |
| Signing | eth gem | EIP-712 for Hyperliquid |
| Frontend | React + Vite + TypeScript | Rich charting, React Router |
| Deployment | Docker Compose | Simple VPS setup |

## Project Structure

```
HyperSense/
├── backend/                         # Rails 8 API
│   ├── app/
│   │   ├── channels/               # ActionCable WebSocket channels
│   │   │   ├── dashboard_channel.rb     # Real-time dashboard updates
│   │   │   └── markets_channel.rb       # Price updates by symbol
│   │   ├── controllers/
│   │   │   └── api/v1/            # REST API endpoints
│   │   │       ├── dashboard_controller.rb
│   │   │       ├── positions_controller.rb
│   │   │       ├── decisions_controller.rb
│   │   │       ├── market_data_controller.rb
│   │   │       ├── macro_strategies_controller.rb
│   │   │       ├── execution_logs_controller.rb
│   │   │       └── costs_controller.rb
│   │   ├── jobs/                   # Solid Queue jobs
│   │   │   ├── trading_cycle_job.rb
│   │   │   ├── macro_strategy_job.rb
│   │   │   ├── market_snapshot_job.rb
│   │   │   ├── risk_monitoring_job.rb
│   │   │   └── forecast_job.rb          # Prophet ML predictions
│   │   ├── models/
│   │   │   ├── market_snapshot.rb   # Time-series market data
│   │   │   ├── macro_strategy.rb    # Daily macro analysis
│   │   │   ├── trading_decision.rb  # Per-asset trade decisions
│   │   │   ├── position.rb          # Open/closed positions
│   │   │   ├── order.rb             # Exchange orders
│   │   │   ├── execution_log.rb     # Audit trail
│   │   │   ├── forecast.rb          # Price predictions with MAE/MAPE
│   │   │   └── account_balance.rb   # Balance history for PnL tracking
│   │   └── services/
│   │       ├── data_ingestion/
│   │       │   ├── price_fetcher.rb      # Binance API
│   │       │   ├── sentiment_fetcher.rb  # Fear & Greed Index
│   │       │   ├── news_fetcher.rb       # RSS news (coinjournal.net)
│   │       │   └── whale_alert_fetcher.rb # Large transfers (whale-alert.io)
│   │       ├── forecasting/
│   │       │   └── price_predictor.rb    # Prophet ML forecasting
│   │       ├── indicators/
│   │       │   └── calculator.rb         # EMA, RSI, MACD, Pivots
│   │       ├── llm/
│   │       │   ├── client.rb             # LLM-agnostic client wrapper
│   │       │   └── errors.rb             # Custom LLM error classes
│   │       ├── reasoning/
│   │       │   ├── context_assembler.rb  # Weighted context for LLM
│   │       │   ├── decision_parser.rb    # JSON validation (dry-validation)
│   │       │   ├── high_level_agent.rb   # Macro strategy (daily)
│   │       │   └── low_level_agent.rb    # Trade decisions (5 min)
│   │       ├── execution/
│   │       │   ├── hyperliquid_client.rb   # Exchange API wrapper
│   │       │   ├── account_manager.rb     # Account state
│   │       │   ├── position_manager.rb    # Position tracking
│   │       │   ├── order_executor.rb      # Order execution
│   │       │   └── balance_sync_service.rb # Balance tracking & deposit/withdrawal detection
│   │       ├── risk/
│   │       │   ├── risk_manager.rb       # Centralized risk validation
│   │       │   ├── position_sizer.rb     # Risk-based position sizing
│   │       │   ├── stop_loss_manager.rb  # SL/TP enforcement
│   │       │   └── circuit_breaker.rb    # Trading halt on losses
│   │       ├── costs/
│   │       │   ├── calculator.rb         # Main cost orchestrator
│   │       │   ├── trading_fee_calculator.rb  # Hyperliquid fee calculations
│   │       │   └── llm_cost_calculator.rb     # LLM API cost estimation
│   │       └── trading_cycle.rb     # Main orchestrator
│   ├── config/
│   │   ├── settings.yml            # Trading parameters
│   │   ├── recurring.yml           # Job schedules
│   │   ├── queue.yml               # Queue workers
│   │   └── database.yml            # PostgreSQL (port 5433)
│   └── spec/
│       └── services/
│           ├── indicators/calculator_spec.rb
│           └── data_ingestion/
├── frontend/                        # React dashboard (Vite + TypeScript)
│   ├── src/
│   │   ├── api/                   # API client
│   │   ├── components/            # React components
│   │   │   ├── cards/            # AccountSummary, PositionsTable, DecisionLog, etc.
│   │   │   ├── charts/           # EquityCurve, PriceChart
│   │   │   ├── common/           # DataTable, PageLayout
│   │   │   ├── filters/          # DateRangeFilter, SymbolFilter, Pagination, etc.
│   │   │   └── layout/           # Header
│   │   ├── hooks/                # useApi, useWebSocket, useFilters, usePagination
│   │   ├── pages/                # Dashboard, ForecastsPage, MarketSnapshotsPage, etc.
│   │   └── types/                # TypeScript definitions
│   └── package.json
├── docker-compose.yml               # PostgreSQL only
└── .tool-versions                   # Ruby 3.4.4, Node 24.11.1
```

## Requirements

- Ruby 3.4.4 (via asdf)
- Node.js 24.11.1 (via asdf)
- PostgreSQL 16 (via Docker)
- Docker & Docker Compose

## Setup

1. **Install Ruby and Node via asdf**
   ```bash
   asdf install
   ```

2. **Install dependencies**
   ```bash
   cd backend
   bundle install
   ```

3. **Configure environment variables**
   ```bash
   cp .env.example .env
   # Edit .env to customize database settings, LLM provider and add Hyperliquid credentials
   ```

4. **Start PostgreSQL** (uses port 5433 to avoid conflicts with local PostgreSQL)
   ```bash
   docker compose up -d
   ```

   The default `.env` settings connect to the Docker PostgreSQL container automatically.

5. **Setup database**
   ```bash
   cd backend
   rails db:create db:migrate
   ```

6. **Configure API keys** (edit `.env` file created in step 3)
   ```bash
   # Database (defaults work with docker-compose)
   DATABASE_HOST=localhost
   DATABASE_PORT=5433
   DATABASE_USER=hypersense
   DATABASE_PASSWORD=hypersense_dev

   # For remote databases, use DATABASE_URL instead:
   # DATABASE_URL=postgresql://user:password@host:5432/hypersense

   # LLM Provider: anthropic, gemini, ollama, or openai
   LLM_PROVIDER=anthropic

   # Anthropic (required if LLM_PROVIDER=anthropic)
   ANTHROPIC_API_KEY=your_anthropic_api_key
   ANTHROPIC_MODEL=claude-sonnet-4-5

   # Gemini (required if LLM_PROVIDER=gemini)
   # GEMINI_API_KEY=your_gemini_api_key
   # GEMINI_MODEL=gemini-2.0-flash-exp

   # OpenAI (required if LLM_PROVIDER=openai)
   # OPENAI_API_KEY=your_openai_api_key
   # OPENAI_MODEL=gpt-5.2

   # Ollama (required if LLM_PROVIDER=ollama)
   # OLLAMA_API_BASE=http://localhost:11434/v1
   # OLLAMA_MODEL=llama3

   # Required: Hyperliquid credentials for trading
   HYPERLIQUID_PRIVATE_KEY=your_wallet_private_key
   HYPERLIQUID_ADDRESS=your_wallet_address
   ```

7. **Test data pipeline**
   ```bash
   rails runner "MarketSnapshotJob.perform_now"
   ```

8. **Run the server**
   ```bash
   bin/dev
   ```

9. **Start background jobs**
   ```bash
   bin/jobs
   ```

10. **Start the frontend** (new terminal)
    ```bash
    cd frontend
    npm install
    npm run dev
    ```

    The dashboard will be available at http://localhost:5173

## Configuration

Edit `config/settings.yml` to customize:

```yaml
# Trading Assets
assets:
  - BTC
  - ETH
  - SOL
  - BNB

# Trading Cycle Configuration
trading:
  cycle_interval_minutes: 5
  paper_trading: true            # Safe mode - no real trades

# Risk Management
risk:
  max_position_size: 0.05        # Max 5% of capital per trade
  min_confidence: 0.6            # Minimum confidence score
  max_leverage: 10
  default_leverage: 3

# Context Weights for Reasoning
weights:
  technical: 0.50
  sentiment: 0.25
  forecast: 0.15
  whale_alerts: 0.10

# Cost Tracking
costs:
  trading:
    taker_fee_pct: 0.000450       # 0.0450% per transaction
    maker_fee_pct: 0.000150       # 0.0150% per transaction
    default_order_type: taker
  server:
    monthly_cost: 15.00           # Monthly server cost
  llm:
    anthropic:
      claude-sonnet-4-5:
        input_per_million: 3.00
        output_per_million: 15.00
    openai:
      gpt-5.2:
        input_per_million: 1.75
        output_per_million: 14.00
    # ... other models (gemini, ollama)
```

## Current Implementation

### 1. Data Collection (MarketSnapshotJob - every minute)

Fetches prices from Binance API, calculates technical indicators, and stores market snapshots.

```ruby
# Trigger manually
MarketSnapshotJob.perform_now

# Example output:
# BTC: $97000.0 | RSI: 60.1 | MACD: 46.03
# ETH: $3200.0  | RSI: 66.0 | MACD: 1.98
# SOL: $190.0   | RSI: 45.0 | MACD: -0.0
# BNB: $700.0   | RSI: 60.1 | MACD: 0.68
```

**MarketSnapshot Model:**
```ruby
# Get latest snapshot for BTC
snapshot = MarketSnapshot.latest_for("BTC")
snapshot.price           # => 97000.0
snapshot.rsi_signal      # => :neutral / :oversold / :overbought
snapshot.macd_signal     # => :bullish / :bearish
snapshot.atr_signal      # => :low_volatility / :normal_volatility / :high_volatility / :very_high_volatility
snapshot.above_ema?(50)  # => true/false

# ATR volatility bands (as % of price):
# - :low_volatility       (ATR < 1%)
# - :normal_volatility    (1% <= ATR < 2%)
# - :high_volatility      (2% <= ATR < 3%)
# - :very_high_volatility (ATR >= 3%)

# Query historical data
MarketSnapshot.for_symbol("ETH").last_hours(24)
MarketSnapshot.prices_for("BTC", limit: 150)  # For indicator calculation
```

### 2. Technical Indicators

Calculated during data collection by `Indicators::Calculator`:

```ruby
calculator = Indicators::Calculator.new

# EMA (Exponential Moving Average)
calculator.ema(prices, 20)   # EMA-20
calculator.ema(prices, 50)   # EMA-50
calculator.ema(prices, 100)  # EMA-100
calculator.ema(prices, 200)  # EMA-200 (long-term trend, bull/bear market structure)

# RSI (Relative Strength Index)
calculator.rsi(prices, 14)   # 0-100, oversold < 30, overbought > 70

# MACD
calculator.macd(prices)      # { macd:, signal:, histogram: }

# ATR (Average True Range) - Volatility indicator
calculator.atr(candles, 14)  # Absolute ATR value

# Pivot Points
calculator.pivot_points(high, low, close)  # { pp:, r1:, r2:, s1:, s2: }
```

### 3. Price Forecasting (ForecastJob - every 5 min)

Prophet-based ML predictions for multiple timeframes.

```ruby
# Generate forecasts for all assets
ForecastJob.perform_now

# Or use the predictor directly
predictor = Forecasting::PricePredictor.new("BTC")
forecasts = predictor.predict_all_timeframes
# => { "1m" => Forecast, "15m" => Forecast, "1h" => Forecast }

# Forecast model
forecast = Forecast.latest_for("BTC", "1h")
forecast.current_price      # => 97000.0
forecast.predicted_price    # => 97500.0
forecast.direction          # => "bullish" / "bearish" / "neutral"
forecast.predicted_change_pct # => 0.52

# Validate past predictions against actual prices
predictor.validate_past_forecasts
# Updates forecast records with actual_price, mae, mape
```

### 4. News & Whale Alerts (Real-time)

External signals for sentiment analysis and smart money tracking.

```ruby
# News from RSS feed (coinjournal.net)
fetcher = DataIngestion::NewsFetcher.new
news = fetcher.fetch
# => [{ title: "Bitcoin...", published_at: Time, symbols: ["BTC"], ... }]

# Filter news for specific assets
fetcher.fetch_for_symbols(["BTC", "ETH"])

# Whale alerts (whale-alert.io)
whale_fetcher = DataIngestion::WhaleAlertFetcher.new
alerts = whale_fetcher.fetch
# => [{ amount: "1,580 BTC", usd_value: "$138M", action: "transferred...", severity: 6, signal: :neutral }]

# Signal interpretation:
# - :potentially_bullish (stablecoin minted, exchange outflow)
# - :potentially_bearish (exchange inflow)
# - :neutral (general transfers)
```

### 5. Weighted Context System

LLM agents receive data with assigned weights for prioritization.

```ruby
# Context weights from settings.yml
weights = {
  technical: 0.50,    # EMA, RSI, MACD, ATR, Pivots (PRIMARY signal)
  sentiment: 0.25,    # Fear & Greed + News
  forecast: 0.15,     # Prophet ML price predictions
  whale_alerts: 0.10  # Large capital movements
}

# Context assembler includes all weighted data
assembler = Reasoning::ContextAssembler.new(symbol: "BTC")
context = assembler.for_trading(macro_strategy: MacroStrategy.active)
# Includes: forecast, news, whale_alerts, market_data, technical_indicators, sentiment

# Technical indicators include:
# - EMA (20, 50, 100, 200), RSI, MACD, Pivot Points
# - ATR with volatility classification (low/normal/high/very_high)

# LLM system prompt instructs to weight inputs accordingly:
# "When data sources conflict, weight your decision according to these priorities."
```

### 6. Macro Strategy (MacroStrategyJob - daily at 6am)

High-level market analysis that sets the trading bias for the day.

The macro strategy agent receives comprehensive market context including:
- **Technical indicators**: EMA, RSI, MACD, ATR (with volatility classification), Pivot Points
- **Market sentiment**: Fear & Greed Index, recent news
- **Price forecasts**: Prophet ML predictions
- **Whale alerts**: Large capital movements

ATR volatility classification helps calibrate risk tolerance:
- High ATR (volatile markets) → Lower risk tolerance recommended
- Low ATR (calm markets) → Higher risk tolerance possible

```ruby
# Runs daily at 6am via MacroStrategyJob
strategy = Reasoning::HighLevelAgent.new.analyze

strategy.bias            # => "bullish" / "bearish" / "neutral"
strategy.risk_tolerance  # => 0.7 (scale 0.0-1.0)
strategy.market_narrative # => "Bitcoin showing strength above 50-day EMA..."
strategy.support_for("BTC")    # => [95000, 92000]
strategy.resistance_for("BTC") # => [100000, 105000]

# Check freshness
MacroStrategy.active       # => Current valid strategy
MacroStrategy.needs_refresh?  # => true if stale or missing
```

### 4. Trading Decisions (TradingCycleJob - every 5 min)

Low-level agent generates trade decisions for each asset within the macro bias.

```ruby
# Runs every 5 minutes via TradingCycleJob
agent = Reasoning::LowLevelAgent.new

# Single asset decision
decision = agent.decide(symbol: "BTC", macro_strategy: MacroStrategy.active)

decision.operation   # => "open" / "close" / "hold"
decision.direction   # => "long" / "short"
decision.confidence  # => 0.78
decision.leverage    # => 5
decision.stop_loss   # => 95000
decision.take_profit # => 105000
decision.actionable? # => true (confidence >= 0.6, not hold)

# All assets at once
decisions = agent.decide_all(macro_strategy: MacroStrategy.active)
# => [TradingDecision(BTC), TradingDecision(ETH), TradingDecision(SOL), TradingDecision(BNB)]
```

**LLM Output Schema:**
```json
{
  "operation": "open",
  "symbol": "BTC",
  "direction": "long",
  "leverage": 5,
  "target_position": 0.02,
  "stop_loss": 95000,
  "take_profit": 105000,
  "confidence": 0.78,
  "reasoning": "RSI neutral at 62, MACD bullish crossover, price above all EMAs"
}
```

### 4.1 Position Direction Evaluation (Long vs Short)

HyperSense supports both **long** and **short** positions symmetrically. The direction decision follows a two-stage process:

#### Stage 1: Macro Strategy Sets the Bias

The `HighLevelAgent` (daily at 6am) analyzes weighted market data to set the trading bias:

| Bias | Meaning | Favored Direction |
|------|---------|-------------------|
| **Bullish** | Market expected to rise | Long positions |
| **Bearish** | Market expected to fall | Short positions |
| **Neutral** | No clear direction | No directional preference |

The bias is determined by weighted inputs:
- **TECHNICAL (50%)** - EMA, RSI, MACD indicators (primary signal)
- **SENTIMENT (25%)** - Fear & Greed Index + news
- **FORECAST (15%)** - Prophet ML price predictions
- **WHALE_ALERTS (10%)** - Large capital movements

#### Stage 2: Low-Level Agent Aligns with Bias

The `LowLevelAgent` (every 5 min) receives the macro context and follows this decision logic:

| Position State | Signal | Macro Bias | Action |
|----------------|--------|------------|--------|
| No position | Bullish signals | Bullish | **Open LONG** |
| No position | Bearish signals | Bearish | **Open SHORT** |
| No position | Unclear signals | Any | HOLD |
| Has position | Target reached | Any | CLOSE |
| Has position | Trend continues | Any | HOLD |

**Key insight**: The LLM is explicitly instructed (in the system prompt) to align trade direction with the macro bias. If the macro strategy is bullish, the agent will prefer long positions; if bearish, it will prefer shorts.

#### Order Execution Mapping

```
direction: "long"  → Exchange order: side: "buy"
direction: "short" → Exchange order: side: "sell"
```

#### PnL Calculation by Direction

| Direction | Profit When | Loss When |
|-----------|-------------|-----------|
| **Long** | `current_price > entry_price` | `current_price < entry_price` |
| **Short** | `current_price < entry_price` | `current_price > entry_price` |

#### Stop-Loss / Take-Profit by Direction

| Direction | SL Triggers When | TP Triggers When |
|-----------|------------------|------------------|
| **Long** | `price <= stop_loss_price` | `price >= take_profit_price` |
| **Short** | `price >= stop_loss_price` | `price <= take_profit_price` |

### 5. Risk Validation

Decisions are validated before execution via `Risk::RiskManager`:

```ruby
# Centralized risk validation
risk_manager = Risk::RiskManager.new
result = risk_manager.validate(decision, entry_price: 100_000)
result.approved?           # => true/false
result.rejection_reason    # => "Confidence 0.5 below minimum 0.6"

# Risk-based position sizing
sizer = Risk::PositionSizer.new
result = sizer.calculate(
  entry_price: 100_000,
  stop_loss: 95_000,
  direction: "long"
)
result[:size]       # => 0.02 (BTC)
result[:risk_amount] # => 100 ($)
```

**Risk Configuration (`config/settings.yml`):**
```yaml
risk:
  max_position_size: 0.05        # 5% of capital max
  min_confidence: 0.6            # 60% confidence threshold
  max_leverage: 10               # Max leverage allowed
  default_leverage: 3            # Default leverage
  max_open_positions: 5          # Max concurrent positions
  max_risk_per_trade: 0.01       # 1% of capital at risk per trade
  min_risk_reward_ratio: 2.0     # Minimum R/R ratio (2:1)
  enforce_risk_reward_ratio: true # Reject below min R/R (false = warn only)
  max_daily_loss: 0.05           # 5% max daily loss (circuit breaker)
  max_consecutive_losses: 3      # Consecutive losses before halt
  circuit_breaker_cooldown: 24   # Hours to wait after trigger
```

### 5.1 Risk Profiles (Cautious / Moderate / Fearless)

Risk Profiles allow users to adjust the trading agent's behavior based on their risk tolerance. Each profile defines different parameters for RSI thresholds, minimum confidence, leverage, and position limits.

**Available Profiles:**

| Profile | RSI Oversold | RSI Overbought | Min Confidence | Default Leverage | Max Positions |
|---------|--------------|----------------|----------------|------------------|---------------|
| **Cautious** | 35 | 65 | 70% | 2x | 3 |
| **Moderate** (default) | 30 | 70 | 60% | 3x | 5 |
| **Fearless** | 25 | 75 | 50% | 5x | 7 |

**How Profiles Affect Trading:**

- **RSI Thresholds**: Define when an asset is considered oversold (buy signal) or overbought (sell signal)
- **Min Confidence**: LLM decisions below this threshold are rejected
- **Default Leverage**: Applied when the LLM doesn't specify leverage
- **Max Positions**: Limits concurrent open positions

**API Endpoints:**

```ruby
# Get current profile
GET /api/v1/risk_profile/current
# => { name: "moderate", parameters: { rsi_oversold: 30, ... }, updated_at: "..." }

# Switch profile
PUT /api/v1/risk_profile/switch
# Body: { profile: "fearless" }
# => { name: "fearless", parameters: { ... }, updated_at: "..." }
```

**Code Usage:**

```ruby
# Get current profile parameters
RiskProfile.current_name        # => "moderate"
RiskProfile.current_parameters  # => { rsi_oversold: 30, rsi_overbought: 70, ... }

# Access via ProfileService (used throughout the system)
Risk::ProfileService.current_name           # => "moderate"
Risk::ProfileService.rsi_oversold           # => 30
Risk::ProfileService.min_confidence         # => 0.6
Risk::ProfileService.default_leverage       # => 3
Risk::ProfileService.max_open_positions     # => 5

# Switch profile
RiskProfile.switch_to!("fearless")
```

**Audit Trail:**

Each trading decision stores the active profile name at creation time (`risk_profile_name` column). This enables:
- Debugging decisions made under different profiles
- Analyzing performance by profile
- Understanding agent behavior when profiles are switched mid-session

**WebSocket Updates:**

When a profile is switched, a `risk_profile_update` message is broadcast to all connected dashboard clients, enabling real-time UI updates.

### 6. Risk Monitoring (RiskMonitoringJob - every minute)

Continuous monitoring of open positions for SL/TP triggers and circuit breaker status.

**Stop-Loss / Take-Profit:**
```ruby
sl_manager = Risk::StopLossManager.new
results = sl_manager.check_all_positions
# => { triggered: [...], checked: 5, skipped: 1 }

# Position risk fields
position = Position.open.find_by(symbol: "BTC")
position.stop_loss_price      # => 95000
position.take_profit_price    # => 110000
position.risk_amount          # => 500 ($)
position.stop_loss_triggered?(94_000)  # => true
position.take_profit_triggered?        # => false
position.risk_reward_ratio    # => 3.0
position.stop_loss_distance_pct # => 5.0 (%)
```

**Circuit Breaker & `trading_allowed`:**

The circuit breaker is a safety mechanism that automatically halts all trading when risk thresholds are breached. It protects against catastrophic losses during adverse market conditions or strategy failures.

**What `trading_allowed` means:**
- `true` - Trading engine can execute new trades normally
- `false` - All trading is halted; the system will only monitor existing positions (SL/TP)

**Trigger conditions** (any one triggers the breaker):

| Condition | Setting | Default | Example |
|-----------|---------|---------|---------|
| Daily loss exceeds threshold | `max_daily_loss` | 5% | Lost $500 on $10,000 account |
| Consecutive losing trades | `max_consecutive_losses` | 3 | 3 losses in a row |

**How it works:**
1. `RiskMonitoringJob` runs every minute and calls `check_and_update!`
2. When a position closes with a loss, `record_loss(amount)` is called
3. If thresholds are exceeded, `trigger!` halts trading and starts cooldown
4. After cooldown (default 24h), trading resumes automatically
5. Winning trades reset the consecutive losses counter

**State storage:** Uses Rails.cache with automatic daily expiry for loss tracking.

**API exposure:**
- `/api/v1/health` returns `trading_allowed: true/false` (used by frontend Header)
- Dashboard shows `circuit_breaker.daily_loss` and `circuit_breaker.consecutive_losses`

```ruby
breaker = Risk::CircuitBreaker.new

# Check before any trade
unless breaker.trading_allowed?
  Rails.logger.warn "Circuit breaker active: #{breaker.trigger_reason}"
  return # Skip trade execution
end

# After trades
breaker.record_loss(500)   # Record losing trade
breaker.record_win(200)    # Record winning trade (resets consecutive losses)

# Full status
breaker.status
# => {
#      trading_allowed: true,
#      daily_loss: 500,
#      daily_loss_pct: 0.05,
#      consecutive_losses: 1,
#      triggered: false,
#      trigger_reason: nil,
#      cooldown_until: nil
#    }

# Manual reset (admin use)
breaker.reset!
```

### 7. Execution Layer (Paper Trading)

The execution layer is implemented with paper trading support. Real order placement requires enhancing the hyperliquid gem with write operations.

**Position Model:**
```ruby
# Track open positions
position = Position.open.find_by(symbol: "BTC")
position.direction       # => "long"
position.size           # => 0.1
position.entry_price    # => 100000
position.pnl_percent    # => 5.0 (%)
position.unrealized_pnl # => 500.0 (USD)
```

**Order Execution (Paper Trading):**
```ruby
# Execute a trading decision
executor = Execution::OrderExecutor.new
order = executor.execute(decision)

order.status           # => "filled" (simulated)
order.filled_size      # => 0.1
order.average_fill_price # => 100050
```

**Account Management:**
```ruby
manager = Execution::AccountManager.new

# Fetch account state from Hyperliquid
state = manager.fetch_account_state
state[:account_value]    # => 10000.0
state[:available_margin] # => 8000.0

# Check if can trade
manager.can_trade?(margin_required: 1000) # => true/false
```

**Position Sync from Hyperliquid:**
```ruby
pm = Execution::PositionManager.new

# Sync positions from exchange
pm.sync_from_hyperliquid
# => { created: 2, updated: 0, closed: 0 }

# Update prices
pm.update_prices
```

### 8. Cost Management

On-the-fly cost tracking for trading fees, LLM API costs, and server costs. No database migrations required - all calculations performed at query time.

About LLM API costs, the cost calculator uses these assumptions:
- Utilization factor: 70% of max_tokens used on average
- Input/Output ratio: 3:1 (trading prompts have extensive market context)

```
Per-Call Token Estimates

| Agent               | Max Output | Est. Output | Est. Input | Total/Call |
|---------------------|------------|-------------|------------|------------|
| Low-level (trading) | 1,500      | 1,050       | 3,150      | 4,200      |
| High-level (macro)  | 2,000      | 1,400       | 4,200      | 5,600      |

Daily Call Volume (at 5-min frequency)

Trading cycles:    24 hours × 60 min ÷ 5 min = 288 cycles/day
Assets per cycle:  4 (BTC, ETH, SOL, BNB)
Total LLM calls:   288 × 4 = 1,152 calls/day
Plus macro:        1 call/day

Daily Token Totals

Trading input:   1,152 calls × 3,150 tokens = 3,628,800 tokens
Trading output:  1,152 calls × 1,050 tokens = 1,209,600 tokens
Macro input:     4,200 tokens
Macro output:    1,400 tokens
─────────────────────────────────────────────────────────────
Total input:     ~3.63M tokens/day
Total output:    ~1.21M tokens/day

---
Corrected Daily Cost Calculation

Formula: (input_tokens × input_price / 1M) + (output_tokens × output_price / 1M)

| Model                | Input $/1M | Output $/1M | Input Cost | Output Cost | Daily Total |
|----------------------|------------|-------------|------------|-------------|-------------|
| claude-sonnet-4-5    | $3.00      | $15.00      | $10.89     | $18.15      | $29.04      |
| gpt-5.2              | $1.75      | $14.00      | $6.35      | $16.94      | $23.29      |
| claude-haiku-4-5     | $1.00      | $5.00       | $3.63      | $6.05       | $9.68       |
| gemini-2.0-flash-exp | $0.50      | $3.00       | $1.82      | $3.63       | $5.45       |
| gpt-5-mini           | $0.25      | $2.00       | $0.91      | $2.42       | $3.33       |

---
Monthly Cost Projection (30 days)

| Model                | Daily  | Monthly |
|----------------------|--------|---------|
| claude-sonnet-4-5    | $29.04 | $871    |
| gpt-5.2              | $23.29 | $699    |
| claude-haiku-4.5     | $9.68  | $290    |
| gemini-2.0-flash-exp | $5.45  | $164    |
| gpt-5-mini           | $0.25  | $100    |
```

**Cost Calculator:**
```ruby
calculator = Costs::Calculator.new

# Get cost summary for a period
summary = calculator.summary(period: :today)
# => {
#   trading_fees: { total: 5.23, ... },
#   llm_costs: { total: 0.12, provider: "anthropic", model: "claude-sonnet-4-5" },
#   server_cost: { daily_rate: 0.50, monthly: 15.00 },
#   total_costs: 5.85
# }

# Get net P&L (gross - trading fees)
net = calculator.net_pnl(period: :today)
# => { gross_realized_pnl: 150.0, trading_fees: 5.23, net_realized_pnl: 144.77 }
```

**Trading Fee Calculator:**
```ruby
fee_calc = Costs::TradingFeeCalculator.new

# Fees for a specific position
fees = fee_calc.for_position(position)
# => { entry_fee: 4.50, exit_fee: 4.50, total_fees: 9.00, entry_notional: 10000 }

# Estimate fees before trading
fee_calc.estimate(notional_value: 10_000, round_trip: true)
# => 9.00 (taker rate: 0.0450% × 2)
```

**Position Fee Methods:**
```ruby
position = Position.find_by(symbol: "BTC")
position.entry_fee        # => 4.50
position.exit_fee         # => 4.50
position.total_fees       # => 9.00
position.net_pnl          # => 140.50 (gross P&L - fees)
position.fee_breakdown    # => { entry_fee: 4.50, exit_fee: 4.50, ... }
```

**LLM Cost Estimation:**
```ruby
llm_calc = Costs::LLMCostCalculator.new

# Estimated costs based on call counts and token settings
costs = llm_calc.estimated_costs(since: 24.hours.ago)
# => {
#   total: 0.12,
#   provider: "anthropic",
#   model: "claude-sonnet-4-5",
#   call_count: 15,
#   estimated_input_tokens: 45000,
#   estimated_output_tokens: 15000
# }
```

### 9. Balance Tracking

Track account balance history for accurate PnL calculation that accounts for deposits and withdrawals.

**Problem Solved:** Without balance tracking, all-time PnL is calculated only from local Position records. If the user made trades outside HyperSense or deposited/withdrew funds, the PnL would be inaccurate.

**Solution:** The `BalanceSyncService` tracks balance history and detects deposits/withdrawals by comparing balance changes with expected PnL from closed positions.

**AccountBalance Model:**
```ruby
# Get balance history
AccountBalance.latest           # => Most recent balance record
AccountBalance.initial          # => First (initial) balance record
AccountBalance.total_deposits   # => Sum of all deposit amounts
AccountBalance.total_withdrawals # => Sum of all withdrawal amounts

# Event types: initial, sync, deposit, withdrawal, adjustment
balance = AccountBalance.latest
balance.event_type    # => "deposit"
balance.balance       # => 15000.0
balance.delta         # => 5000.0 (change from previous)
```

**BalanceSyncService:**
```ruby
service = Execution::BalanceSyncService.new

# Sync balance from Hyperliquid (called automatically during TradingCycle)
result = service.sync!
# => { created: true, balance: 15000.0, event_type: "deposit" }

# Calculate accurate PnL (accounts for deposits/withdrawals)
service.calculated_pnl
# => 1000.0 (current - initial - deposits + withdrawals)

# Get balance history summary
service.balance_history
# => {
#   initial_balance: 10000.0,
#   current_balance: 16000.0,
#   total_deposits: 5000.0,
#   total_withdrawals: 0.0,
#   calculated_pnl: 1000.0,
#   last_sync: Time
# }
```

**PnL Formula:**
```
calculated_pnl = current_balance - initial_balance - total_deposits + total_withdrawals
```

**Detection Threshold:** Changes below $1 are treated as normal trading activity. Larger unexplained changes are classified as deposits (if positive) or withdrawals (if negative).

---

## Development Status

### Phase 1: Foundation ✅
- [x] Rails 8 API setup
- [x] PostgreSQL + Docker (port 5433)
- [x] Solid Queue configuration
- [x] Service architecture
- [x] RSpec + VCR setup

### Phase 2: Data Pipeline ✅
- [x] Price fetcher (Binance API)
- [x] Sentiment fetcher (Fear & Greed Index)
- [x] Technical indicators (EMA, RSI, MACD, Pivot Points)
- [x] MarketSnapshot model with JSONB indicators
- [x] MarketSnapshotJob (runs every minute)

### Phase 3: Reasoning Engine ✅
- [x] MacroStrategy model (bias, risk tolerance, key levels)
- [x] TradingDecision model (operation, direction, confidence)
- [x] ContextAssembler (market data, indicators, sentiment)
- [x] HighLevelAgent (daily macro strategy via Claude Sonnet)
- [x] LowLevelAgent (5-min trade decisions via Claude Sonnet)
- [x] DecisionParser with dry-validation JSON schemas

### Phase 4: Hyperliquid Integration ✅
- [x] Position, Order, ExecutionLog models
- [x] HyperliquidClient (read operations via forked gem)
- [x] AccountManager (account state, margin calculations)
- [x] PositionManager (position sync, tracking)
- [x] OrderExecutor (paper trading mode)
- [x] TradingCycle integration
- [ ] Write operations (requires gem enhancement - see `docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md`)

### Phase 5: Risk Management ✅
- [x] Position sizing (risk-based, configurable max risk per trade)
- [x] Stop-loss / Take-profit (stored in Position, enforced by RiskMonitoringJob)
- [x] Circuit breakers (daily loss limits, consecutive loss limits, cooldown)
- [x] Risk/reward validation (configurable enforcement)
- [x] Centralized risk validation (Risk::RiskManager)
- [x] Paper trading mode (already implemented in Phase 4)

### Phase 5.1: Predictive Modeling & Weighted Context ✅
- [x] Weighted context system (technical: 0.50, sentiment: 0.25, forecast: 0.15, whale_alerts: 0.10)
- [x] Prophet-based price forecasting (1m, 15m, 1h predictions)
- [x] Forecast model with MAE/MAPE validation tracking
- [x] News fetcher (RSS from coinjournal.net)
- [x] Whale alert fetcher (whale-alert.io free endpoint)
- [x] Context assembler integration with all new data sources
- [x] LLM prompts updated with weight instructions

### Phase 6: Dashboard ✅
- [x] React frontend (Vite + TypeScript)
- [x] Equity curve (recharts)
- [x] Position tracking
- [x] Decision logs
- [x] ActionCable WebSocket real-time updates
- [x] API v1 controllers (dashboard, positions, decisions, market_data, macro_strategies)
- [x] Market overview with forecasts and indicators
- [x] System status monitoring
- [x] React Router with detail pages (decisions, strategies, forecasts, snapshots)
- [x] Reusable filter components (date range, symbol, status, search, pagination)
- [x] Paginated list endpoints with filters
- [x] CostSummaryCard component (Trading fee, LLM cost estimation etc.)

### Phase 7: Production
- [x] Dockerfile (backend + frontend)
- [x] docker-compose.yml (full stack orchestration)
- [ ] Monitoring/alerting

---

## Implementation Plan

### Completed Phases

**Phase 3: Multi-Agent Reasoning Engine** - See "Current Implementation" section for details.

**Phase 4: Hyperliquid Integration** - See "Current Implementation" section for details.
- Note: Write operations still require gem enhancement - see `docs/HYPERLIQUID_GEM_WRITE_OPERATIONS_SPEC.md`

**Phase 5: Risk Management** - See "Current Implementation" section for details.

### Phase 6: React Dashboard (Completed)

**API Endpoints:**

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/health` | GET | App status, version, paper_trading, trading_allowed |
| `/api/v1/dashboard` | GET | Aggregated dashboard data |
| `/api/v1/dashboard/account` | GET | Account summary |
| `/api/v1/dashboard/system_status` | GET | System health status |
| `/api/v1/positions` | GET | All positions (paginated) |
| `/api/v1/positions/open` | GET | Open positions with summary |
| `/api/v1/positions/performance` | GET | Equity curve and statistics |
| `/api/v1/decisions` | GET | Trading decisions (paginated) |
| `/api/v1/decisions/recent` | GET | Last N decisions |
| `/api/v1/decisions/stats` | GET | Decision statistics |
| `/api/v1/market_data/current` | GET | Current prices and indicators |
| `/api/v1/market_data/:symbol/history` | GET | Historical price data |
| `/api/v1/market_data/forecasts` | GET | Price forecasts (aggregated or paginated list) |
| `/api/v1/market_data/snapshots` | GET | Market snapshots (paginated with filters) |
| `/api/v1/macro_strategies` | GET | Macro strategies (paginated) |
| `/api/v1/macro_strategies/current` | GET | Active macro strategy |
| `/api/v1/execution_logs` | GET | Execution logs (paginated with filters) |
| `/api/v1/execution_logs/:id` | GET | Single execution log details |
| `/api/v1/execution_logs/stats` | GET | Execution statistics (success rate, by action) |
| `/api/v1/costs/summary` | GET | Cost breakdown for period (trading fees, LLM, server) |
| `/api/v1/costs/llm` | GET | Detailed LLM cost breakdown |
| `/api/v1/costs/trading` | GET | Detailed trading fee breakdown |
| `/api/v1/orders` | GET | Orders (paginated with filters) |
| `/api/v1/orders/:id` | GET | Single order with full details |
| `/api/v1/orders/active` | GET | Pending and submitted orders |
| `/api/v1/orders/stats` | GET | Order statistics (counts, fill rate, slippage) |
| `/api/v1/account_balances` | GET | Balance history (paginated with filters) |
| `/api/v1/account_balances/:id` | GET | Single balance record details |
| `/api/v1/account_balances/summary` | GET | Balance summary with calculated PnL |

**WebSocket Channels:**

```javascript
// Connect to dashboard channel for real-time updates
const subscription = cable.subscriptions.create("DashboardChannel", {
  received(data) {
    // data.type: market_update, position_update, decision_update, macro_strategy_update
    console.log(data);
  }
});

// Connect to markets channel for price updates
const markets = cable.subscriptions.create({ channel: "MarketsChannel", symbol: "BTC" }, {
  received(data) {
    console.log(data);
  }
});
```

**Dashboard Components:**

- **AccountSummary** - Open positions, unrealized PnL, margin used, daily P&L, aggregated volatility badge
- **MarketOverview** - Current prices, RSI, MACD, EMA signals, forecasts, per-coin volatility with ATR %
- **PositionsTable** - Open positions with entry price, current price, PnL (gross/net), SL/TP
- **EquityCurve** - Cumulative PnL chart with win rate and statistics
- **MacroStrategyCard** - Current market bias, risk tolerance, narrative, key levels
- **DecisionLog** - Recent trading decisions with volatility badge, LLM model, reasoning
- **SystemStatus** - Health status of market data, trading cycle, macro strategy, next cycle timing
- **CostSummaryCard** - Net P&L, trading fees, LLM costs, server costs breakdown

**Detail Pages (with React Router):**

| Route | Page | Features |
|-------|------|----------|
| `/` | Dashboard | Main dashboard with all cards |
| `/decisions` | DecisionsPage | Trading decisions with status, operation, symbol, volatility filters |
| `/macro-strategies` | MacroStrategiesPage | Strategy history with bias filter, expandable narrative |
| `/forecasts` | ForecastsPage | Price forecasts with symbol, timeframe, date filters |
| `/market-snapshots` | MarketSnapshotsPage | Market snapshots with RSI/MACD signals, expandable indicators |
| `/execution-logs` | ExecutionLogsPage | Execution logs with status, action filters, expandable payloads |

**Filter Components:**

- **DateRangeFilter** - Date range with 24h, 7d, 30d presets
- **SymbolFilter** - Dropdown for BTC, ETH, SOL, BNB
- **StatusFilter** - Generic status/bias/operation dropdown
- **SearchFilter** - Debounced text search (300ms)
- **Pagination** - Page navigation with size selector
- **DataTable** - Generic table with loading skeleton, empty state, expandable rows

### Phase 7: Production (Completed)

**Docker Setup:**

Run the full stack with a single command:

```bash
# Setup
cp .env.docker.example .env
# Edit .env with your API keys and RAILS_MASTER_KEY

# Run
docker compose up -d --build

# Access
http://localhost

# Logs
docker compose logs -f

# Stop
docker compose down
```

**docker-compose.yml** (at project root):
```yaml
services:
  db:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backend/docker/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U hypersense"]

  backend:
    build: ./backend
    environment:
      RAILS_ENV: production
      SOLID_QUEUE_IN_PUMA: "false"
    depends_on:
      db: { condition: service_healthy }

  worker:
    build: ./backend
    command: ["./bin/jobs"]
    depends_on:
      backend: { condition: service_healthy }

  frontend:
    build: ./frontend
    ports:
      - "80:80"
    depends_on:
      backend: { condition: service_healthy }
```

**Architecture:**
- **db**: PostgreSQL 16 with multi-database init (primary, cache, queue, cable)
- **backend**: Rails API via Thruster (port 80 internal)
- **worker**: Solid Queue background jobs
- **frontend**: React SPA via Nginx with API/WebSocket proxy

**Recommended VPS:** 2GB RAM minimum (DigitalOcean, Hetzner, Linode)

---

## Confirmed Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Language | Ruby (Rails 8) | User expertise 10/10, excellent for scheduled jobs |
| Job Queue | Solid Queue | No Redis needed, PostgreSQL-backed |
| Target DEX | Hyperliquid | Best for perps, good API |
| Dashboard | Rails API + React | Rich charting, TypeScript |
| Agent Structure | Multi-agent | High-level (macro) + Low-level (execution) |
| Deployment | Local / VPS | Docker Compose |

---

## Testing

```bash
cd backend

# Run all specs
rspec

# Run specific specs
rspec spec/services/indicators/calculator_spec.rb

# Test data pipeline manually
rails runner "MarketSnapshotJob.perform_now"
rails runner "puts MarketSnapshot.count"
```

---

## Related Repositories

- [Hyperliquid Ruby Gem](https://github.com/marcomd/hyperliquid) - Forked for write operations

## License

Private - All rights reserved
