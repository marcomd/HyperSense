# frozen_string_literal: true

# Tracks open and closed trading positions on Hyperliquid
#
# Positions are created when orders are filled and represent the current
# exposure to a specific asset. They track entry price, size, leverage,
# unrealized PnL, and risk parameters (stop-loss, take-profit).
#
# == Schema Information
#
# Table name: positions
#
#  id                :bigint           not null, primary key
#  symbol            :string           not null
#  direction         :string           not null (long/short)
#  size              :decimal          not null
#  entry_price       :decimal          not null
#  current_price     :decimal
#  leverage          :integer          default(1)
#  margin_used       :decimal
#  unrealized_pnl    :decimal          default(0)
#  liquidation_price :decimal
#  status            :string           default("open")
#  hyperliquid_data  :jsonb            default({})
#  opened_at         :datetime         not null
#  closed_at         :datetime
#  stop_loss_price   :decimal
#  take_profit_price :decimal
#  risk_amount       :decimal          # $ at risk based on SL distance
#  realized_pnl      :decimal          default(0)
#  close_reason      :string           # sl_triggered, tp_triggered, manual, signal
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
class Position < ApplicationRecord
  VALID_STATUSES = %w[open closing closed].freeze
  VALID_DIRECTIONS = %w[long short].freeze
  VALID_CLOSE_REASONS = %w[sl_triggered tp_triggered manual signal liquidated].freeze

  # Associations
  has_many :orders, dependent: :nullify
  has_many :execution_logs, as: :loggable, dependent: :destroy

  # Validations
  validates :symbol, presence: true
  validates :direction, presence: true, inclusion: { in: VALID_DIRECTIONS }
  validates :status, presence: true, inclusion: { in: VALID_STATUSES }
  validates :size, presence: true, numericality: { greater_than: 0 }
  validates :entry_price, presence: true, numericality: { greater_than: 0 }
  validates :leverage, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }
  validates :close_reason, inclusion: { in: VALID_CLOSE_REASONS }, allow_nil: true
  validates :stop_loss_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :take_profit_price, numericality: { greater_than: 0 }, allow_nil: true
  validates :risk_amount, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Scopes
  scope :open, -> { where(status: "open") }
  scope :closed, -> { where(status: "closed") }
  scope :closing, -> { where(status: "closing") }
  scope :for_symbol, ->(symbol) { where(symbol: symbol) }
  scope :long, -> { where(direction: "long") }
  scope :short, -> { where(direction: "short") }
  scope :recent, -> { order(opened_at: :desc) }

  # Callbacks
  before_validation :set_opened_at, on: :create

  # State transitions

  # Mark position as closing (order submitted to close)
  def mark_closing!
    update!(status: "closing")
  end

  # Close the position with reason and realized PnL
  # @param reason [String] Close reason (sl_triggered, tp_triggered, manual, signal)
  # @param pnl [Numeric, nil] Realized PnL (uses unrealized_pnl if nil)
  def close!(reason: "manual", pnl: nil)
    update!(
      status: "closed",
      closed_at: Time.current,
      close_reason: reason,
      realized_pnl: pnl || unrealized_pnl || 0
    )
  end

  # Status helpers

  def open?
    status == "open"
  end

  def closed?
    status == "closed"
  end

  def closing?
    status == "closing"
  end

  # Direction helpers

  def long?
    direction == "long"
  end

  def short?
    direction == "short"
  end

  # Calculations

  # Calculate unrealized PnL as percentage
  # @return [Float] PnL percentage (positive = profit)
  def pnl_percent
    return 0 if current_price.nil? || entry_price.zero?

    if long?
      ((current_price - entry_price) / entry_price * 100).to_f
    else
      ((entry_price - current_price) / entry_price * 100).to_f
    end
  end

  # Calculate notional value of position
  # @return [BigDecimal] size * entry_price
  def notional_value
    size * entry_price
  end

  # Update current price and recalculate unrealized PnL
  # @param new_price [Numeric] Current market price
  def update_current_price!(new_price)
    pnl = if long?
      size * (new_price - entry_price)
    else
      size * (entry_price - new_price)
    end

    update!(current_price: new_price, unrealized_pnl: pnl)
  end

  # Update position from Hyperliquid API data
  # @param data [Hash] Position data from Hyperliquid user_state
  def update_from_hyperliquid!(data)
    update!(
      current_price: data["markPx"]&.to_d,
      unrealized_pnl: data["unrealizedPnl"]&.to_d,
      liquidation_price: data["liquidationPx"]&.to_d,
      margin_used: data["marginUsed"]&.to_d,
      hyperliquid_data: data
    )
  end

  # Risk Management

  # Check if position has stop-loss configured
  # @return [Boolean]
  def has_stop_loss?
    stop_loss_price.present?
  end

  # Check if position has take-profit configured
  # @return [Boolean]
  def has_take_profit?
    take_profit_price.present?
  end

  # Check if stop-loss should trigger at current price
  # @param price [Numeric, nil] Price to check (defaults to current_price)
  # @return [Boolean] true if SL should trigger
  def stop_loss_triggered?(price = current_price)
    return false if stop_loss_price.nil? || price.nil?

    if long?
      price <= stop_loss_price
    else
      price >= stop_loss_price
    end
  end

  # Check if take-profit should trigger at current price
  # @param price [Numeric, nil] Price to check (defaults to current_price)
  # @return [Boolean] true if TP should trigger
  def take_profit_triggered?(price = current_price)
    return false if take_profit_price.nil? || price.nil?

    if long?
      price >= take_profit_price
    else
      price <= take_profit_price
    end
  end

  # Calculate risk/reward ratio for this position
  # @return [Float, nil] Risk/reward ratio (e.g., 2.0 means 2:1)
  def risk_reward_ratio
    return nil if stop_loss_price.nil? || take_profit_price.nil?

    risk = (entry_price - stop_loss_price).abs
    reward = (take_profit_price - entry_price).abs

    return nil if risk.zero?

    (reward / risk).to_f
  end

  # Distance from current price to stop-loss in percentage
  # @return [Float, nil] Percentage distance (positive = safe buffer)
  def stop_loss_distance_pct
    return nil if stop_loss_price.nil? || current_price.nil?

    if long?
      ((current_price - stop_loss_price) / current_price * 100).to_f
    else
      ((stop_loss_price - current_price) / current_price * 100).to_f
    end
  end

  # Distance from current price to take-profit in percentage
  # @return [Float, nil] Percentage distance (positive = not yet reached)
  def take_profit_distance_pct
    return nil if take_profit_price.nil? || current_price.nil?

    if long?
      ((take_profit_price - current_price) / current_price * 100).to_f
    else
      ((current_price - take_profit_price) / current_price * 100).to_f
    end
  end

  # Trading Fees (calculated on-the-fly)

  # Calculate entry fee for this position
  # @return [Float] Entry fee in USD
  def entry_fee
    fee_breakdown[:entry_fee]
  end

  # Calculate exit fee for this position
  # @return [Float] Exit fee in USD (estimated if position is open)
  def exit_fee
    fee_breakdown[:exit_fee]
  end

  # Calculate total round-trip fees
  # @return [Float] Total fees in USD
  def total_fees
    entry_fee + exit_fee
  end

  # Calculate net P&L (gross - fees)
  # @return [Float] Net P&L in USD
  def net_pnl
    gross = closed? ? realized_pnl.to_f : unrealized_pnl.to_f
    gross - total_fees
  end

  # Get complete fee breakdown from the calculator
  # @return [Hash] Fee details for this position
  def fee_breakdown
    @fee_breakdown ||= Costs::TradingFeeCalculator.new.for_position(self)
  end

  private

  def set_opened_at
    self.opened_at ||= Time.current
  end
end
