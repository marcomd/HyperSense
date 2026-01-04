# frozen_string_literal: true

# Stores the currently active risk profile for the trading system.
#
# This is a singleton model - only one record should exist at any time.
# The profile affects RSI thresholds, risk/reward ratios, position sizing,
# and other trading parameters.
#
# @example Get current profile
#   RiskProfile.current      # => #<RiskProfile name: "moderate">
#   RiskProfile.current_name # => "moderate"
#
# @example Switch profiles
#   RiskProfile.switch_to!("fearless", changed_by: "dashboard")
#
class RiskProfile < ApplicationRecord
  # Valid profile names
  PROFILES = %w[cautious moderate fearless].freeze

  validates :name, presence: true, inclusion: { in: PROFILES }

  # Returns the current (and only) risk profile record.
  # Creates a default "moderate" profile if none exists.
  #
  # @return [RiskProfile] the current risk profile
  def self.current
    first_or_create!(name: "moderate", changed_by: "system")
  end

  # Returns the name of the current profile.
  #
  # @return [String] profile name (cautious, moderate, or fearless)
  def self.current_name
    current.name
  end

  # Switches to the specified profile.
  #
  # @param profile_name [String] the profile to switch to
  # @param changed_by [String] who initiated the change (default: "api")
  # @raise [ArgumentError] if profile_name is not valid
  # @return [RiskProfile] the updated profile
  def self.switch_to!(profile_name, changed_by: "api")
    raise ArgumentError, "Invalid profile: #{profile_name}" unless PROFILES.include?(profile_name)

    current.update!(name: profile_name, changed_by: changed_by)
    current
  end
end
