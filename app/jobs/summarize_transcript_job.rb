# frozen_string_literal: true

class SummarizeTranscriptJob < ApplicationJob
  queue_as :default

  def perform(transcript_id)
    transcript = Transcript.find_by(id: transcript_id)
    return unless transcript&.completed?

    Summarizer.new(transcript).summarize
  end
end
