Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      resources :agents, only: [:index, :show, :create] do
          member do
            get :memories
            get :transcripts
          end
        end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
