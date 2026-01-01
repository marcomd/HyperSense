# frozen_string_literal: true

# Records each trading decision made by the low-level agent
#
# Tracks the full context sent to the LLM, raw response, parsed decision,
# and execution status for audit trail and learning.
#
# == Schema Information
#
# Table name: trading_decisions
#
#  id                   :bigint           not null, primary key
#  macro_strategy_id    :bigint
#  symbol               :string           not null
#  context_sent         :jsonb            default({})
#  llm_response         :jsonb            default({})
#  parsed_decision      :jsonb            default({})
#  operation            :string           (open/close/hold)
#  direction            :string           (long/short)
#  confidence           :decimal(3, 2)    (0.00 - 1.00)
#  executed             :boolean          default(FALSE)
#  rejection_reason     :string
#  status               :string           default("pending")
#  volatility_level     :integer          default(2)  (0=very_high, 1=high, 2=medium, 3=low)
#  atr_value            :decimal(20, 8)
#  next_cycle_interval  :integer          default(12) (minutes)
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#
class TradingDecision < ApplicationRecord
  VALID_STATUSES = %w[pending approved rejected executed failed].freeze
  VALID_OPERATIONS = %w[open close hold].freeze
  VALID_DIRECTIONS = %w[long short].freeze

  # Volatility levels for dynamic job scheduling
  # Maps to Indicators::VolatilityClassifier levels
  enum :volatility_level, {
    very_high: 0,
    high: 1,
    medium: 2,
    low: 3
  }, prefix: :volatility

  # Associations
  belongs_to :macro_strategy, optional: true

  # Validations
  validates :symbol, presence: true
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :operation, inclusion: { in: VALID_OPERATIONS }, allow_nil: true
  validates :direction, inclusion: { in: VALID_DIRECTIONS }, allow_nil: true
  validates :confidence, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 1
  }, allow_nil: true
  validates :next_cycle_interval, numericality: {
    greater_than: 0,
    less_than_or_equal_to: 30
  }, allow_nil: true

  # Scopes
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :recent, -> { order(created_at: :desc) }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :executed, -> { where(status: "executed") }
  scope :actionable, -> { where(operation: %w[open close]) }
  scope :holds, -> { where(operation: "hold") }

  # State transitions

  # Approve the decision for execution
  def approve!
    update!(status: "approved")
  end

  # Reject the decision with a reason
  # @param reason [String] Reason for rejection
  def reject!(reason)
    update!(status: "rejected", rejection_reason: reason)
  end

  # Mark the decision as successfully executed
  def mark_executed!
    update!(status: "executed", executed: true)
  end

  # Mark the decision as failed during execution
  # @param reason [String] Reason for failure
  def mark_failed!(reason)
    update!(status: "failed", rejection_reason: reason)
  end

  # Helpers

  # Check if decision is approved
  # @return [Boolean]
  def approved?
    status == "approved"
  end

  # Check if decision is actionable (open or close, not hold)
  # @return [Boolean]
  def actionable?
    %w[open close].include?(operation)
  end

  # Check if decision is a hold
  # @return [Boolean]
  def hold?
    operation == "hold"
  end

  # Extract leverage from parsed_decision
  # @return [Integer, nil]
  def leverage
    parsed_decision["leverage"]&.to_i
  end

  # Extract target_position from parsed_decision
  # @return [Float, nil]
  def target_position
    parsed_decision["target_position"]&.to_f
  end

  # Extract stop_loss from parsed_decision
  # @return [Float, nil]
  def stop_loss
    parsed_decision["stop_loss"]&.to_f
  end

  # Extract take_profit from parsed_decision
  # @return [Float, nil]
  def take_profit
    parsed_decision["take_profit"]&.to_f
  end

  # Extract reasoning from parsed_decision
  # @return [String, nil]
  def reasoning
    parsed_decision["reasoning"]
  end
end
