# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Protect from forgery attacks in web requests
  protect_from_forgery with: :exception

  # Skip CSRF protection for API requests (detected by format)
  skip_before_action :verify_authenticity_token, if: :api_request?

  private

  def api_request?
    request.format.json? || request.path.start_with?('/api/')
  end
end
