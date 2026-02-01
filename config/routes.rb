Rails.application.routes.draw do
  # Health check
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # Authentication
  resource :admin, only: %i[new create]
  resource :session, only: %i[new create destroy]

  # Setup wizard
  resource :setup, only: %i[new create], controller: 'setup'

  # Dashboard
  root 'dashboard#show'

  # Individual service actions
  resources :services, only: [] do
    member do
      get :version
      get :status
      post :start
      post :stop
      post :restart
    end
  end
end
