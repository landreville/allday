# frozen_string_literal: true

class TranscriptChannel < ApplicationCable::Channel
  def subscribed
    transcript = current_user.agents.joins(:transcripts)
                              .where(transcripts: {id: params[:transcript_id]})
                              .first&.transcripts&.find_by(id: params[:transcript_id])

    if transcript
      stream_from "transcript_#{transcript.id}"
      Rails.logger.info "User #{current_user.id} subscribed to transcript #{transcript.id}"
    else
      reject
      Rails.logger.warn "User #{current_user.id} attempted to subscribe to unauthorized transcript #{params[:transcript_id]}"
    end
  end

  def unsubscribed
    Rails.logger.info "User #{current_user.id} unsubscribed from transcript channel"
  end
end