# frozen_string_literal: true

FactoryBot.define do
  factory :agent do
    user
    sequence(:name) { |n| "agent-#{n}" }
    llm_model { "claude-sonnet-4-6" }
    origin { :blank_slate }
    model_config { {} }
    metadata { {} }
  end
end
