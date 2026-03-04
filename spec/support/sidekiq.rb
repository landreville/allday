# frozen_string_literal: true

# Configure Sidekiq for test environment
RSpec.configure do |config|
  config.before(:suite) do
    # Use fake adapter for Sidekiq in tests (new API)
    Sidekiq.configure_client do |config|
      config.redis = {url: "redis://fake"}
    end

    # Enable fake mode for job testing
    require "sidekiq/testing"
    Sidekiq::Testing.fake!

    # Clear all Sidekiq jobs before running tests
    Sidekiq::Worker.clear_all
  end

  config.before(:each) do
    # Clear jobs before each test
    Sidekiq::Worker.clear_all
  end

  # Helper methods for testing Sidekiq jobs
  config.include(Module.new do
    def sidekiq_jobs
      Sidekiq::Worker.jobs
    end

    def clear_sidekiq_jobs
      Sidekiq::Worker.clear_all
    end
  end)
end
