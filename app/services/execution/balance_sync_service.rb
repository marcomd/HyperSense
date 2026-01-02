# frozen_string_literal: true

module Execution
  # Syncs account balance from Hyperliquid and detects deposits/withdrawals.
  #
  # This service tracks balance history to enable accurate PnL calculation.
  # By comparing balance changes with expected PnL from closed positions,
  # it can distinguish between trading gains/losses and external deposits/withdrawals.
  #
  # == Usage
  #
  #   service = Execution::BalanceSyncService.new
  #   service.sync!  # Creates AccountBalance record
  #   service.calculated_pnl  # Returns accurate PnL excluding deposits/withdrawals
  #
  # == PnL Formula
  #
  #   PnL = current_balance - initial_balance - total_deposits + total_withdrawals
  #
  class BalanceSyncService
    # Minimum unexplained balance change to trigger deposit/withdrawal detection.
    # Small changes (< $1) are treated as rounding errors or minor PnL changes.
    DEPOSIT_WITHDRAWAL_THRESHOLD = 1.0

    # Minimum change to record a new balance entry (avoids database bloat)
    MIN_CHANGE_THRESHOLD = 0.01

    def initialize(client: nil)
      @client = client || HyperliquidClient.new
      @account_manager = AccountManager.new(client: @client)
      @logger = Rails.logger
    end

    # Sync current balance from Hyperliquid.
    # Creates a new AccountBalance record if balance changed significantly.
    #
    # @return [Hash] Result of the sync operation
    #   - { skipped: true, reason: "..." } if sync was skipped
    #   - { created: true, balance: ..., event_type: "..." } if record created
    def sync!
      return { skipped: true, reason: "not_configured" } unless @client.configured?

      @logger.info "[BalanceSyncService] Starting balance sync..."

      current_balance = fetch_current_balance
      last_record = AccountBalance.latest

      if last_record.nil?
        create_initial_record(current_balance)
      else
        detect_and_record_change(current_balance, last_record)
      end
    end

    # Calculate accurate PnL accounting for deposits and withdrawals.
    #
    # Formula: current_balance - initial_balance - deposits + withdrawals
    #
    # @return [BigDecimal] Calculated PnL
    def calculated_pnl
      initial = AccountBalance.initial_capital || 0
      current = AccountBalance.current_balance || 0
      deposits = AccountBalance.total_deposits
      withdrawals = AccountBalance.total_withdrawals

      current - initial - deposits + withdrawals
    end

    # Get summary of balance history for dashboard.
    #
    # @return [Hash] Balance history summary
    def balance_history
      {
        initial_balance: AccountBalance.initial_capital&.to_f,
        current_balance: AccountBalance.current_balance&.to_f,
        total_deposits: AccountBalance.total_deposits.to_f,
        total_withdrawals: AccountBalance.total_withdrawals.to_f,
        calculated_pnl: calculated_pnl.to_f,
        last_sync: AccountBalance.latest&.recorded_at
      }
    end

    private

    # Fetch current balance from Hyperliquid
    # @return [Float] Current account value
    def fetch_current_balance
      account_state = @account_manager.fetch_account_state
      @hyperliquid_data = account_state[:raw_response]
      account_state[:account_value]
    end

    # Create the first balance record (initial capital)
    # @param balance [Float] Current balance
    # @return [Hash] Result hash
    def create_initial_record(balance)
      record = AccountBalance.create!(
        balance: balance,
        event_type: "initial",
        source: "hyperliquid",
        hyperliquid_data: @hyperliquid_data || {},
        recorded_at: Time.current
      )

      @logger.info "[BalanceSyncService] Created initial balance record: $#{balance}"

      {
        created: true,
        balance: balance,
        event_type: "initial",
        record_id: record.id
      }
    end

    # Detect balance change and determine if it's from trading or deposit/withdrawal
    # @param current_balance [Float] Current balance from Hyperliquid
    # @param last_record [AccountBalance] Previous balance record
    # @return [Hash] Result hash
    def detect_and_record_change(current_balance, last_record)
      delta = current_balance - last_record.balance

      # Skip if no significant change
      if delta.abs < MIN_CHANGE_THRESHOLD
        @logger.debug "[BalanceSyncService] No significant change (delta: #{delta})"
        return { skipped: true, reason: "no_change" }
      end

      # Calculate expected PnL change from closed positions since last sync
      expected_pnl_change = calculate_pnl_change_since(last_record.recorded_at)

      # Determine event type based on unexplained difference
      event_type = determine_event_type(delta, expected_pnl_change)

      create_record(
        balance: current_balance,
        previous_balance: last_record.balance,
        delta: delta,
        event_type: event_type,
        expected_pnl: expected_pnl_change
      )
    end

    # Calculate realized PnL from positions closed since given time.
    # Also considers change in unrealized PnL from open positions.
    #
    # @param since [Time] Start time for PnL calculation
    # @return [Float] Expected PnL change
    def calculate_pnl_change_since(since)
      # Realized PnL from closed positions
      realized = Position.closed
                         .where("closed_at >= ?", since)
                         .sum(:realized_pnl)
                         .to_f

      # Note: We don't track unrealized PnL changes here because they're
      # already reflected in the balance. This method focuses on explaining
      # what portion of the balance change is from trading activity.

      realized
    end

    # Determine event type based on delta vs expected PnL.
    # If the difference between actual delta and expected PnL is significant,
    # it indicates a deposit or withdrawal.
    #
    # @param delta [Float] Actual balance change
    # @param expected_pnl_change [Float] PnL change from closed positions
    # @return [String] Event type (sync, deposit, or withdrawal)
    def determine_event_type(delta, expected_pnl_change)
      unexplained = delta - expected_pnl_change

      if unexplained.abs < DEPOSIT_WITHDRAWAL_THRESHOLD
        "sync" # Change is explained by trading activity
      elsif unexplained > DEPOSIT_WITHDRAWAL_THRESHOLD
        "deposit" # Unexplained increase
      else
        "withdrawal" # Unexplained decrease
      end
    end

    # Create a new balance record
    # @param balance [Float] Current balance
    # @param previous_balance [Float] Previous balance
    # @param delta [Float] Change amount
    # @param event_type [String] Event classification
    # @param expected_pnl [Float] Expected PnL from trading
    # @return [Hash] Result hash
    def create_record(balance:, previous_balance:, delta:, event_type:, expected_pnl:)
      notes = build_notes(event_type, delta, expected_pnl)

      record = AccountBalance.create!(
        balance: balance,
        previous_balance: previous_balance,
        delta: delta,
        event_type: event_type,
        source: "hyperliquid",
        notes: notes,
        hyperliquid_data: @hyperliquid_data || {},
        recorded_at: Time.current
      )

      @logger.info "[BalanceSyncService] Created #{event_type} record: " \
                   "$#{previous_balance} -> $#{balance} (delta: #{delta > 0 ? '+' : ''}#{delta})"

      {
        created: true,
        balance: balance,
        delta: delta,
        event_type: event_type,
        record_id: record.id
      }
    end

    # Build notes for the record explaining the classification
    # @param event_type [String] Event classification
    # @param delta [Float] Balance change
    # @param expected_pnl [Float] Expected PnL from trading
    # @return [String, nil] Notes or nil
    def build_notes(event_type, delta, expected_pnl)
      case event_type
      when "deposit"
        unexplained = delta - expected_pnl
        "External deposit detected. Balance change: $#{delta.round(2)}, " \
        "Expected PnL: $#{expected_pnl.round(2)}, Unexplained: $#{unexplained.round(2)}"
      when "withdrawal"
        unexplained = delta - expected_pnl
        "External withdrawal detected. Balance change: $#{delta.round(2)}, " \
        "Expected PnL: $#{expected_pnl.round(2)}, Unexplained: $#{unexplained.round(2)}"
      end
    end
  end
end
