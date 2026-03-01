# frozen_string_literal: true

FactoryBot.define do
  factory :transcript do
    agent
    source { "claude-code" }
    source_session_id { SecureRandom.uuid }
    status { :active }
    started_at { Time.current }
    metadata { {} }
  end
end
