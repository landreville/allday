# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: %i[index show create] do
        member do
          get :memories
          get :transcripts
        end
      end
      get "memories/search", to: "memories#search"
      post "transcripts/import", to: "transcripts#import"
      resources :transcripts, only: %i[show create update] do
        resources :messages, only: %i[index create]
      end

      # Claude Code streaming endpoints
      post "claude_code/session_start", to: "claude_code#session_start"
      post "claude_code/session_end", to: "claude_code#session_end"
      post "claude_code/stream_event", to: "claude_code#stream_event"
    end
  end

  get "up" => "rails/health#show", :as => :rails_health_check

  # ActionCable WebSocket endpoint
  mount ActionCable.server => "/cable"
end
