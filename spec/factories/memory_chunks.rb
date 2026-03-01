# frozen_string_literal: true

FactoryBot.define do
  factory :memory_chunk do
    transcript
    agent { transcript.agent }
    topic { "implemented feature" }
    summary { "Did some work on a feature." }
    embedding { Array.new(1536) { rand(-1.0..1.0) } }
    skills_demonstrated { %w[ruby testing] }
    message_range_start { 1 }
    message_range_end { 10 }
  end
end
