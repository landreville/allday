Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show, :create] do
          member do
            get :memories
            get :transcripts
          end
        end
      get "memories/search", to: "memories#search"
      post "transcripts/import", to: "transcripts#import"
      resources :transcripts, only: [:show, :create, :update] do
        resources :messages, only: [:index, :create]
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
