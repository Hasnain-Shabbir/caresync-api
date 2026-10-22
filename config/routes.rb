Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, skip: :all

  post "/graphql", to: "graphql#execute"

  get "/sandbox", to: "sandbox#show" if Rails.env.development?
end
