ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.

# Load dotenv EARLY so forked Solid Queue workers inherit ENV vars
# This must happen before any forking occurs
require "dotenv"
env_file = File.expand_path("../.env", __dir__)
Dotenv.load(env_file) if File.exist?(env_file)
