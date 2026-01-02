# frozen_string_literal: true

# Tracks account balance history for accurate PnL calculation.
#
# AccountBalance records are created during each trading cycle to track
# balance changes over time. By comparing balance deltas with expected
# PnL changes, the system can detect deposits and withdrawals, enabling
# accurate all-time PnL calculation.
#
# == Event Types
#
# - initial: First balance recorded (baseline for PnL calculation)
# - sync: Normal balance update from trading activity
# - deposit: External funds added to account
# - withdrawal: Funds removed from account
# - adjustment: Manual correction (e.g., reconciliation)
#
# == Schema Information
#
# Table name: account_balances
#
#  id               :bigint           not null, primary key
#  balance          :decimal          not null (current balance)
#  previous_balance :decimal          (balance from last record)
#  delta            :decimal          (change since last record)
#  event_type       :string           not null (initial, sync, deposit, withdrawal, adjustment)
#  source           :string           default("hyperliquid")
#  notes            :text
#  hyperliquid_data :jsonb            default({})
#  recorded_at      :datetime         not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class AccountBalance < ApplicationRecord
  VALID_EVENT_TYPES = %w[initial sync deposit withdrawal adjustment].freeze

  # Validations
  validates :balance, presence: true, numericality: true
  validates :event_type, presence: true, inclusion: { in: VALID_EVENT_TYPES }
  validates :recorded_at, presence: true
  validates :previous_balance, numericality: true, allow_nil: true
  validates :delta, numericality: true, allow_nil: true

  # Scopes
  scope :initial_records, -> { where(event_type: "initial") }
  scope :syncs, -> { where(event_type: "sync") }
  scope :deposits, -> { where(event_type: "deposit") }
  scope :withdrawals, -> { where(event_type: "withdrawal") }
  scope :adjustments, -> { where(event_type: "adjustment") }
  scope :recent, -> { order(recorded_at: :desc) }
  scope :chronological, -> { order(recorded_at: :asc) }
  scope :by_event_type, ->(type) { where(event_type: type) }
  scope :since, ->(time) { where("recorded_at >= ?", time) }

  # Callbacks
  before_validation :set_recorded_at, on: :create

  # Class methods

  # Get the most recent balance record
  # @return [AccountBalance, nil]
  def self.latest
    recent.first
  end

  # Get the initial balance record (first one created)
  # @return [AccountBalance, nil]
  def self.initial
    initial_records.chronological.first
  end

  # Calculate total deposits since initial balance
  # @return [BigDecimal] Sum of all deposit deltas
  def self.total_deposits
    deposits.sum(:delta) || 0
  end

  # Calculate total withdrawals since initial balance
  # @return [BigDecimal] Sum of all withdrawal deltas (as positive number)
  def self.total_withdrawals
    withdrawals.sum(:delta)&.abs || 0
  end

  # Get current balance (from latest record)
  # @return [BigDecimal, nil]
  def self.current_balance
    latest&.balance
  end

  # Get initial capital (from initial record)
  # @return [BigDecimal, nil]
  def self.initial_capital
    initial&.balance
  end

  # Instance methods - event type predicates

  # Check if this is the initial balance record
  # @return [Boolean]
  def initial?
    event_type == "initial"
  end

  # Check if this is a normal sync record
  # @return [Boolean]
  def sync?
    event_type == "sync"
  end

  # Check if this is a deposit event
  # @return [Boolean]
  def deposit?
    event_type == "deposit"
  end

  # Check if this is a withdrawal event
  # @return [Boolean]
  def withdrawal?
    event_type == "withdrawal"
  end

  # Check if this is a manual adjustment
  # @return [Boolean]
  def adjustment?
    event_type == "adjustment"
  end

  # Check if balance increased
  # @return [Boolean]
  def increased?
    delta.present? && delta.positive?
  end

  # Check if balance decreased
  # @return [Boolean]
  def decreased?
    delta.present? && delta.negative?
  end

  private

  def set_recorded_at
    self.recorded_at ||= Time.current
  end
end
