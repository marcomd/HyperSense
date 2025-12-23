# HyperSense

## Technical Specifications: Autonomous AI Trading Agent  

The system is designed as an autonomous agent that operates in discrete cycles to analyze market data and execute trades without human intervention.

### 1. System Architecture & Workflow   
- **Operation Cycle:** The agent must wake up at fixed intervals (e.g., every 3 to 15 minutes).  
- **Workflow Sequence:**  
    1. **Data Ingestion:** Fetch market data, technical indicators, and external signals.  
    2. **Context Assembly:** Format all data into a structured prompt for the Reasoning Engine.  
    3. **Reasoning:** The AI processes the context and decides on an action.  
    4. **Execution:** The decision is parsed and sent to the trading platform.  
    5. **Logging:** Every step (data, reasoning, execution) is stored in a relational database for monitoring and backtesting.  


### 2. Data Input Modules (Context)  
The agent requires a multi-faceted input stream to minimize "noise" and improve decision-making.  
2.1 Market & Technical Data  
- **Price Action:** Current price, historical values, and 24h volume for supported assets (e.g., BTC, ETH, SOL, BNB).  
- **Standard Indicators:** EMA (20, 50, 100), MACD, RSI (various timeframes), Open Interest, and Funding Rate.  
- **Advanced Indicators (Pivot Points):** Calculation of Support (S1, S2) and Resistance (R1, R2) levels and the central Pivot Point (PP) to identify trend reversals.  
2.2 External Signals & Sentiment  
- **Market Sentiment:** Fear & Greed Index to understand the psychological state of the market.  
- **Real-time News:** Integration of XML/RSS news feeds or social media updates (e.g., influential figures' posts).  
- **Whale Alerts:** Monitoring of large capital movements (Whale Alert) to predict sudden price shifts.  
2.3 Predictive Modeling  
- **Forecasting Module:** A dedicated model to predict price trends over different timeframes (1 min, 15 min, 1 hour).  
- **Weighted Importance:** Ability to assign manual weights to specific inputs (e.g., Forecast weight: 0.6; Sentiment weight: 0.2) to refine the strategy.  

### 3. Reasoning Engine  
The core logic utilizes a Large Language Model (LLM) capable of structured reasoning.  
- **Chain of Thought:** The model must "think" through its analysis before outputting a decision.  
- **Multi-Agent Structure (Proposed):**  
    - **High-Level Agent:** Analyzes low-frequency data (e.g., weekly) to create a narrative/macro-strategy.  
    - **Low-Level Agent:** Operates at high frequency for precise execution.  
- **Output Format:** The decision must be returned as a structured JSON object containing: `operation`, `symbol`, `direction`, `leverage`, `target_position`, and `reasoning`.  

### 4. Execution & Trading Logic  
- **Platform Integration:** Connectivity with a Decentralized Exchange (DEX) via API for spot and perpetual leverage trading.  
- **Action Space:**  
    - **Open Long/Short:** Initiate a bet on price increase or decrease.  
    - **Hold:** Maintain current positions.  
    - **Close/Exit:** Fully liquidate a position (partial closures are currently not supported).  
- **Leverage:** Variable leverage (e.g., from 1x to 10x or up to 40x for high-risk efficiency).  

### 5. Risk Management & Control  
- **Capital Management:** A dedicated module to filter AI operations, limiting exposure (e.g., max 5% of total capital per trade).  
- **Safety Guards:** Implementation of Stop Loss and Take Profit levels to mitigate volatility between agent wake-up cycles.  
- **Confidence Score:** The agent should output its level of certainty for an action to decide whether to execute it.  

### 6. Monitoring & Evaluation  
- **Live Dashboard:** Visual tracking of the Equity Curve, PNL (Profit and Loss), Win Rate, and open/closed positions history.  
- **Execution Logs:** Full storage of the prompt sent to the AI and its reasoning to debug hallucinations or strategic errors.  
- **Backtesting:** Recording data to simulate strategies on historical values to verify indicator effectiveness.

