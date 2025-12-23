# frozen_string_literal: true

# Tracks orders submitted to Hyperliquid exchange
#
# Orders are created from TradingDecisions and track the lifecycle
# from pending -> submitted -> filled/cancelled/failed.
#
# == Schema Information
#
# Table name: orders
#
#  id                    :bigint           not null, primary key
#  trading_decision_id   :bigint
#  position_id           :bigint
#  symbol                :string           not null
#  order_type            :string           not null (market/limit/stop_limit)
#  side                  :string           not null (buy/sell)
#  size                  :decimal          not null
#  price                 :decimal          (required for limit orders)
#  stop_price            :decimal          (required for stop_limit)
#  status                :string           default("pending")
#  hyperliquid_order_id  :string
#  hyperliquid_response  :jsonb            default({})
#  filled_size           :decimal
#  average_fill_price    :decimal
#  submitted_at          :datetime
#  filled_at             :datetime
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#
class Order < ApplicationRecord
  VALID_STATUSES = %w[pending submitted filled partially_filled cancelled failed].freeze
  VALID_ORDER_TYPES = %w[market limit stop_limit].freeze
  VALID_SIDES = %w[buy sell].freeze

  # Associations
  belongs_to :trading_decision, optional: true
  belongs_to :position, optional: true
  has_many :execution_logs, as: :loggable, dependent: :destroy

  # Validations
  validates :symbol, presence: true
  validates :order_type, presence: true, inclusion: { in: VALID_ORDER_TYPES }
  validates :side, presence: true, inclusion: { in: VALID_SIDES }
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :size, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, if: :requires_price?
  validates :stop_price, presence: true, if: :requires_stop_price?

  # Scopes
  scope :pending, -> { where(status: "pending") }
  scope :submitted, -> { where(status: "submitted") }
  scope :filled, -> { where(status: "filled") }
  scope :partially_filled, -> { where(status: "partially_filled") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :failed, -> { where(status: "failed") }
  scope :active, -> { where(status: %w[pending submitted]) }
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :recent, -> { order(created_at: :desc) }
  scope :buys, -> { where(side: "buy") }
  scope :sells, -> { where(side: "sell") }

  # State transitions

  # Mark order as submitted to exchange
  # @param order_id [String] Hyperliquid order ID
  def submit!(order_id)
    update!(
      status: "submitted",
      hyperliquid_order_id: order_id,
      submitted_at: Time.current
    )
  end

  # Mark order as completely filled
  # @param filled_size [Numeric] Amount filled
  # @param average_price [Numeric] Average fill price
  def fill!(filled_size:, average_price:)
    update!(
      status: "filled",
      filled_size: filled_size,
      average_fill_price: average_price,
      filled_at: Time.current
    )
  end

  # Mark order as partially filled
  # @param filled_size [Numeric] Amount filled so far
  # @param average_price [Numeric] Average fill price so far
  def partially_fill!(filled_size:, average_price:)
    update!(
      status: "partially_filled",
      filled_size: filled_size,
      average_fill_price: average_price
    )
  end

  # Cancel the order
  # @param reason [String, nil] Optional cancellation reason
  def cancel!(reason: nil)
    response = hyperliquid_response || {}
    response["cancel_reason"] = reason if reason
    update!(status: "cancelled", hyperliquid_response: response)
  end

  # Mark order as failed
  # @param error [String] Error message
  def fail!(error)
    response = hyperliquid_response || {}
    response["error"] = error
    update!(status: "failed", hyperliquid_response: response)
  end

  # Status helpers

  def pending?
    status == "pending"
  end

  def submitted?
    status == "submitted"
  end

  def filled?
    status == "filled"
  end

  def partially_filled?
    status == "partially_filled"
  end

  def cancelled?
    status == "cancelled"
  end

  def failed?
    status == "failed"
  end

  def active?
    %w[pending submitted].include?(status)
  end

  # Side helpers

  def buy?
    side == "buy"
  end

  def sell?
    side == "sell"
  end

  # Order type helpers

  def market_order?
    order_type == "market"
  end

  def limit_order?
    order_type == "limit"
  end

  def stop_limit_order?
    order_type == "stop_limit"
  end

  # Calculations

  # Calculate remaining unfilled size
  # @return [BigDecimal]
  def remaining_size
    size - (filled_size || 0)
  end

  # Calculate percentage filled
  # @return [Float]
  def fill_percent
    return 0 if filled_size.nil? || size.zero?
    (filled_size / size * 100).to_f
  end

  private

  def requires_price?
    order_type == "limit" || order_type == "stop_limit"
  end

  def requires_stop_price?
    order_type == "stop_limit"
  end
end
