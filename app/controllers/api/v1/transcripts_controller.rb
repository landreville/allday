# frozen_string_literal: true

module Api
  module V1
    class TranscriptsController < BaseController
      def show
        transcript = find_transcript
        return render json: {error: "Not found"}, status: :not_found unless transcript

        render json: transcript
      end

      def create
        agent = current_user.agents.find_by(id: transcript_params[:agent_id])
        unless agent
          return render json: {errors: ["Agent not found or not owned by you"]}, status: :unprocessable_content
        end

        transcript = agent.transcripts.build(transcript_params.merge(started_at: Time.current))
        if transcript.save
          render json: transcript, status: :created
        else
          render json: {errors: transcript.errors.full_messages}, status: :unprocessable_content
        end
      end

      def update
        transcript = find_transcript
        return render json: {error: "Not found"}, status: :not_found unless transcript

        attrs = transcript_params
        attrs = attrs.merge(completed_at: Time.current) if attrs[:status] == "completed" && transcript.active?

        if transcript.update(attrs)
          SummarizeTranscriptJob.perform_later(transcript.id) if transcript.completed?
          render json: transcript
        else
          render json: {errors: transcript.errors.full_messages}, status: :unprocessable_content
        end
      end

      def import
        agent = current_user.agents.find_by(id: params[:agent_id])
        unless agent
          return render json: {errors: ["Agent not found or not owned by you"]}, status: :unprocessable_content
        end

        transcript = TranscriptImporter.new(
          agent: agent,
          jsonl_content: params[:jsonl],
          source: params[:source] || "claude-code",
          source_session_id: params[:source_session_id],
          metadata: permitted_import_metadata
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
        Transcript.joins(:agent).where(agents: {user_id: current_user.id}).find_by(id: params[:id])
      end

      def transcript_params
        base_params = params.require(:transcript).permit(:agent_id, :source, :source_session_id, :status)

        # Allow specific metadata keys that are commonly used
        if params[:transcript][:metadata].present?
          metadata_params = params[:transcript][:metadata].permit(
            :hook_type, :timestamp, :project_path, :claude_model, :workspace,
            :duration, :total_messages, :total_tools_used, :completion_reason,
            :test, :description, files_modified: []
          )
          base_params[:metadata] = metadata_params.to_h
        end

        base_params
      end

      def permitted_import_metadata
        return {} if params[:metadata].blank?

        params[:metadata].permit(
          :hook_type, :timestamp, :project_path, :claude_model, :workspace,
          :duration, :total_messages, :total_tools_used, :completion_reason,
          :source, :auto_created, :test, :description
        ).to_h
      end
    end
  end
end
