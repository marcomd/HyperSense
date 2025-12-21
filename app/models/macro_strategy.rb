# frozen_string_literal: true

# Stores high-level market analysis from the macro strategist agent
#
# Generated daily (6am) by HighLevelAgent to provide context for
# low-level trading decisions throughout the day.
#
# == Schema Information
#
# Table name: macro_strategies
#
#  id               :bigint           not null, primary key
#  market_narrative :text             not null
#  bias             :string           not null (bullish/bearish/neutral)
#  risk_tolerance   :decimal(3, 2)    not null (0.00 - 1.00)
#  key_levels       :jsonb            default({})
#  context_used     :jsonb            default({})
#  llm_response     :jsonb            default({})
#  valid_until      :datetime         not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
class MacroStrategy < ApplicationRecord
  # Validations
  validates :market_narrative, presence: true
  validates :bias, presence: true, inclusion: { in: %w[bullish bearish neutral] }
  validates :risk_tolerance, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :valid_until, presence: true

  # Scopes
  scope :current, -> { where("valid_until > ?", Time.current).order(created_at: :desc) }
  scope :recent, -> { order(created_at: :desc) }

  class << self
    # Get the currently active macro strategy
    # @return [MacroStrategy, nil] The most recent valid strategy
    def active
      current.first
    end

    # Check if we need a new macro strategy
    # @return [Boolean] True if no valid strategy exists or current one is stale
    def needs_refresh?
      active.nil? || active.stale?
    end
  end

  # Check if strategy is past its valid_until time
  # @return [Boolean] True if strategy is no longer valid
  def stale?
    valid_until <= Time.current
  end

  # Get support levels for a symbol
  # @param symbol [String, Symbol] Asset symbol (e.g., "BTC")
  # @return [Array<Numeric>, nil] Array of support price levels
  def support_for(symbol)
    key_levels&.dig(symbol.to_s.upcase, "support")
  end

  # Get resistance levels for a symbol
  # @param symbol [String, Symbol] Asset symbol (e.g., "BTC")
  # @return [Array<Numeric>, nil] Array of resistance price levels
  def resistance_for(symbol)
    key_levels&.dig(symbol.to_s.upcase, "resistance")
  end

  # Risk-adjusted position size multiplier
  # @return [BigDecimal] The risk tolerance as a multiplier
  def position_multiplier
    risk_tolerance
  end
end
