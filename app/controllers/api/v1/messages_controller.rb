module Api
  module V1
    class MessagesController < BaseController
      def index
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i.clamp(1, 100)

        messages = transcript.messages.offset((page - 1) * per_page).limit(per_page)
        render json: messages
      end

      def create
        transcript = find_transcript
        return render json: { error: "Not found" }, status: :not_found unless transcript

        unless transcript.active?
          return render json: { errors: ["Cannot add messages to a completed transcript"] }, status: :unprocessable_entity
        end

        message = transcript.messages.build(message_params.merge(agent_id: transcript.agent_id))
        if message.save
          render json: message, status: :created
        else
          render json: { errors: message.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def find_transcript
        Transcript.joins(:agent).where(agents: { user_id: current_user.id }).find_by(id: params[:transcript_id])
      end

      def message_params
        params.require(:message).permit(:role, :content, :thinking, :sequence, :timestamp, metadata: {})
      end
    end
  end
end
