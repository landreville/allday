# frozen_string_literal: true

module Api
  module V1
    class BaseController < ApplicationController
      before_action :authenticate!

      private

      def authenticate!
        token = request.headers["Authorization"]&.delete_prefix("Bearer ")
        @current_user = User.find_by(api_key: token)

        return if @current_user

        render json: {error: "Invalid API key"}, status: :unauthorized
      end

      attr_reader :current_user

      def current_agent
        @current_agent ||= if request.headers["X-Agent-Id"].present?
          current_user.agents.find_by(id: request.headers["X-Agent-Id"])
        end
      end
    end
  end
end
