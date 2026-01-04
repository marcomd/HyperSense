# frozen_string_literal: true

module Api
  module V1
    # Manages risk profile selection for the trading system.
    #
    # Allows users to switch between three risk profiles:
    # - cautious: Conservative trading, stricter thresholds
    # - moderate: Balanced approach (default)
    # - fearless: Aggressive trading, relaxed thresholds
    #
    class RiskProfilesController < BaseController
      # GET /api/v1/risk_profile/current
      #
      # Returns the current risk profile and its parameters.
      #
      # @return [JSON] { profile: { name, changed_by, updated_at }, parameters: {...} }
      def current
        profile = RiskProfile.current

        render json: {
          profile: serialize_profile(profile),
          parameters: Risk::ProfileService.current_params
        }
      end

      # PUT /api/v1/risk_profile/switch
      #
      # Switches to a different risk profile.
      # Broadcasts the change via WebSocket for real-time dashboard updates.
      #
      # @param profile [String] Profile name (cautious, moderate, or fearless)
      # @return [JSON] { profile: {...}, parameters: {...}, message: "..." }
      def switch
        profile_name = params.require(:profile)

        unless RiskProfile::PROFILES.include?(profile_name)
          return render json: {
            error: "Invalid profile: #{profile_name}. Valid profiles: #{RiskProfile::PROFILES.join(', ')}"
          }, status: :unprocessable_entity
        end

        RiskProfile.switch_to!(profile_name, changed_by: "dashboard")
        profile = RiskProfile.current

        # Broadcast change via WebSocket
        DashboardChannel.broadcast_risk_profile_update(profile)

        render json: {
          profile: serialize_profile(profile),
          parameters: Risk::ProfileService.current_params,
          message: "Switched to #{profile_name} profile. Takes effect on next trading cycle."
        }
      end

      private

      # Serialize a RiskProfile record for JSON response.
      #
      # @param profile [RiskProfile] The profile to serialize
      # @return [Hash] Serialized profile data
      def serialize_profile(profile)
        {
          name: profile.name,
          changed_by: profile.changed_by,
          updated_at: profile.updated_at.iso8601
        }
      end
    end
  end
end
