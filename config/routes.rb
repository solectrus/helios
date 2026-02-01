Rails.application.routes.draw do
  # Health check
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # Authentication
  resource :admin, only: %i[new create]
  resource :session, only: %i[new create destroy]

  # Setup wizard
  resource :setup, only: %i[new create]

  # Dashboard
  root 'dashboard#show'

  # Service management (RESTful nested resources)
  resources :services, only: [], module: :services do
    resource :version, only: :show
    resource :status, only: :show
    resource :task, only: %i[create update destroy]
  end
end
