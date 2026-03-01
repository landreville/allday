module Api
  module V1
    class TranscriptsController < BaseController
      def show
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        render json: transcript
      end

      def create
        agent = current_user.agents.find_by(id: transcript_params[:agent_id])
        unless agent
          return render json: { errors: ["Agent not found or not owned by you"] }, status: :unprocessable_entity
        end

        transcript = agent.transcripts.build(transcript_params.merge(started_at: Time.current))
        if transcript.save
          render json: transcript, status: :created
        else
          render json: { errors: transcript.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        attrs = transcript_params
        if attrs[:status] == "completed" && transcript.active?
          attrs = attrs.merge(completed_at: Time.current)
        end

        if transcript.update(attrs)
          SummarizeTranscriptJob.perform_later(transcript.id) if transcript.completed?
          render json: transcript
        else
          render json: { errors: transcript.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def import
        agent = current_user.agents.find_by(id: params[:agent_id])
        unless agent
          return render json: { errors: ["Agent not found or not owned by you"] }, status: :unprocessable_entity
        end

        transcript = TranscriptImporter.new(
          agent: agent,
          jsonl_content: params[:jsonl],
          source: params[:source] || "claude-code",
          source_session_id: params[:source_session_id],
          metadata: params[:metadata]&.permit!&.to_h || {}
        ).import

        SummarizeTranscriptJob.perform_later(transcript.id)

        render json: {
          id: transcript.id,
          status: transcript.status,
          message_count: transcript.messages.count,
          agent_id: transcript.agent_id
        }, status: :created
      end

      private

      def find_transcript
        Transcript.joins(:agent).where(agents: { user_id: current_user.id }).find_by(id: params[:id])
      end

      def transcript_params
        params.require(:transcript).permit(:agent_id, :source, :source_session_id, :status, metadata: {})
      end
    end
  end
end
