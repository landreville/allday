module Api
  module V1
    class AgentsController < BaseController
      def index
        agents = current_user.agents
        render json: agents
      end

      def show
        agent = current_user.agents.find_by(id: params[:id])
        if agent
          render json: agent
        else
          render json: { error: "Not found" }, status: :not_found
        end
      end

      def create
        agent = current_user.agents.build(agent_params)
        if agent.save
          render json: agent, status: :created
        else
          render json: { errors: agent.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def memories
        agent = current_user.agents.find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless agent

        chunks = agent.memory_chunks.select(:id, :topic, :summary, :skills_demonstrated,
          :transcript_id, :message_range_start, :message_range_end, :created_at)
        render json: chunks
      end

      def transcripts
        agent = current_user.agents.find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless agent

        render json: agent.transcripts
      end

      private

      def agent_params
        params.require(:agent).permit(:name, :llm_model, :origin, :parent_id, model_config: {}, metadata: {})
      end
    end
  end
end
