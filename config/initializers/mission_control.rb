# frozen_string_literal: true

# Mission Control Jobs Configuration
#
# Configures the Mission Control Jobs dashboard for monitoring Solid Queue.
# HTTP Basic Auth credentials are read from environment variables.
#
# Session middleware is configured in config/application.rb (required for flash messages).
#
# @see https://github.com/rails/mission_control-jobs

MissionControl::Jobs.http_basic_auth_user = ENV.fetch("MISSION_CONTROL_USER", "admin")
MissionControl::Jobs.http_basic_auth_password = ENV.fetch("MISSION_CONTROL_PASSWORD", nil)
