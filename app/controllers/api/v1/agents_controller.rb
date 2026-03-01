module Api
  module V1
    class AgentsController < BaseController
      def index
        agents = current_user.agents
        render json: agents
      end
    end
  end
end
