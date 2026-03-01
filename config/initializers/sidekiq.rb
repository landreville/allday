# frozen_string_literal: true

Sidekiq.configure_server do |config|
  config.redis = {url: ENV.fetch("REDIS_URL", "redis://localhost:6381/0")}
end

Sidekiq.configure_client do |config|
  config.redis = {url: ENV.fetch("REDIS_URL", "redis://localhost:6381/0")}
end
