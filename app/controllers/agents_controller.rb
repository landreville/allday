# frozen_string_literal: true

class AgentsController < ApplicationController
  before_action :authenticate_user!

  def index
    @agents = current_user.agents.includes(:transcripts)
      .order(:name)
  end

  def show
    @agent = current_user.agents.find(params[:id])
    @messages = @agent.messages.includes(:transcript)
      .order(:sequence)
    @memory_chunks = @agent.memory_chunks.includes(:transcript)
      .order(created_at: :desc)
  end

  private

  def current_user
    # For now, using a placeholder - this would normally come from authentication
    User.first || User.create!(email: "demo@allday.ai", name: "Demo User")
  end

  def authenticate_user!
    redirect_to root_path unless current_user
  end
end
