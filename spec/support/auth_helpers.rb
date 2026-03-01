# frozen_string_literal: true

module AuthHelpers
  def auth_headers(user, agent: nil)
    headers = {"Authorization" => "Bearer #{user.api_key}"}
    headers["X-Agent-Id"] = agent.id.to_s if agent
    headers
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
end
