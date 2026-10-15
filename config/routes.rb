Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index"
  # get "organizations" to: "organization#index"
  # get "organizations/:id" to: "organization#show"

  # resources: organizations, only: [:index, :show, :create, :update, :destroy]

  namespace :api do
    namespace :v1 do
      resources :organizations, only: :index
    end
  end
end
