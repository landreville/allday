# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      api_key = request.params[:api_key] || request.headers["Authorization"]&.gsub(/^Bearer\s+/, "")

      if api_key && (user = User.find_by(api_key: api_key))
        user
      else
        reject_unauthorized_connection
      end
    end
  end
end