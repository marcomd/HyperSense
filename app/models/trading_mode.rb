# frozen_string_literal: true

# Stores the user-controlled trading mode.
#
# This is a singleton model - only one record should exist at any time.
# The mode controls whether the system can open/close positions.
#
# Modes:
# - enabled: Normal operation (can open and close positions)
# - exit_only: Only position closures allowed (set automatically by circuit breaker)
# - blocked: Complete halt (no opens or closes)
#
# @example Get current mode
#   TradingMode.current      # => #<TradingMode mode: "enabled">
#   TradingMode.current_mode # => "enabled"
#
# @example Switch modes
#   TradingMode.switch_to!("exit_only", changed_by: "circuit_breaker", reason: "Daily loss exceeded 5%")
#
# @example Check permissions
#   TradingMode.current.can_open?  # => true/false
#   TradingMode.current.can_close? # => true/false
#
class TradingMode < ApplicationRecord
  # Valid trading modes
  MODES = %w[enabled exit_only blocked].freeze

  validates :mode, presence: true, inclusion: { in: MODES }

  # Returns the current (and only) trading mode record.
  # Creates a default "enabled" mode if none exists.
  #
  # @return [TradingMode] the current trading mode
  def self.current
    first_or_create!(mode: "enabled", changed_by: "system")
  end

  # Returns the name of the current mode.
  #
  # @return [String] mode name (enabled, exit_only, or blocked)
  def self.current_mode
    current.mode
  end

  # Switches to the specified mode.
  #
  # @param mode_name [String] the mode to switch to
  # @param changed_by [String] who initiated the change (default: "api")
  # @param reason [String, nil] optional reason for the change
  # @raise [ArgumentError] if mode_name is not valid
  # @return [TradingMode] the updated mode
  def self.switch_to!(mode_name, changed_by: "api", reason: nil)
    raise ArgumentError, "Invalid mode: #{mode_name}" unless MODES.include?(mode_name)

    current.update!(mode: mode_name, changed_by: changed_by, reason: reason)
    current
  end

  # Check if this mode allows opening new positions.
  #
  # @return [Boolean] true if opening positions is allowed
  def can_open?
    mode == "enabled"
  end

  # Check if this mode allows closing positions.
  #
  # @return [Boolean] true if closing positions is allowed
  def can_close?
    mode != "blocked"
  end
end
