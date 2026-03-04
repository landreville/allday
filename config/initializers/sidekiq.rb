# frozen_string_literal: true

# Skip Redis configuration in test environment to avoid connection issues
unless Rails.env.test?
  Sidekiq.configure_server do |config|
    config.redis = {url: ENV.fetch("REDIS_URL", "redis://localhost:6381/0")}
  end

  Sidekiq.configure_client do |config|
    config.redis = {url: ENV.fetch("REDIS_URL", "redis://localhost:6381/0")}
  end
end
