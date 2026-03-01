# frozen_string_literal: true

module Api
  module V1
    class MemoriesController < BaseController
      def search
        return render json: {error: "query parameter is required"}, status: :bad_request if params[:query].blank?

        results = MemorySearchService.new(
          user: current_user,
          query: params[:query],
          agent_id: params[:agent_id],
          skills: params[:skills],
          limit: params[:limit] || 10
        ).search

        render json: results.map { |chunk|
          {
            id: chunk.id,
            topic: chunk.topic,
            summary: chunk.summary,
            skills_demonstrated: chunk.skills_demonstrated,
            agent_id: chunk.agent_id,
            agent_name: chunk.agent.name,
            transcript_id: chunk.transcript_id,
            message_range_start: chunk.message_range_start,
            message_range_end: chunk.message_range_end,
            created_at: chunk.created_at
          }
        }
      end
    end
  end
end
