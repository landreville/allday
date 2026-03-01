# frozen_string_literal: true

FactoryBot.define do
  factory :message do
    transcript
    agent { transcript.agent }
    role { :user }
    content { "Hello" }
    timestamp { Time.current }
    metadata { {} }

    after(:build) do |message|
      message.sequence ||= Message.where(transcript_id: message.transcript_id).maximum(:sequence).to_i + 1
    end
  end
end
