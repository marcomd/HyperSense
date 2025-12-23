# frozen_string_literal: true

# Tracks open and closed trading positions on Hyperliquid
#
# Positions are created when orders are filled and represent the current
# exposure to a specific asset. They track entry price, size, leverage,
# and unrealized PnL.
#
# == Schema Information
#
# Table name: positions
#
#  id               :bigint           not null, primary key
#  symbol           :string           not null
#  direction        :string           not null (long/short)
#  size             :decimal          not null
#  entry_price      :decimal          not null
#  current_price    :decimal
#  leverage         :integer          default(1)
#  margin_used      :decimal
#  unrealized_pnl   :decimal          default(0)
#  liquidation_price:decimal
#  status           :string           default("open")
#  hyperliquid_data :jsonb            default({})
#  opened_at        :datetime         not null
#  closed_at        :datetime
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class Position < ApplicationRecord
  VALID_STATUSES = %w[open closing closed].freeze
  VALID_DIRECTIONS = %w[long short].freeze

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

  # Close the position
  def close!
    update!(status: "closed", closed_at: Time.current)
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

  private

  def set_opened_at
    self.opened_at ||= Time.current
  end
end
