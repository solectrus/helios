Rails.application.routes.draw do
  # Health check
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # Authentication
  resource :admin, only: %i[new create]
  resource :session, only: %i[new create destroy]

  # Setup wizard
  resource :setup, only: %i[new create]

  # Generated files preview
  resource :generated_files, only: :show

  # Sensors live view
  resource :sensors, only: :show do
    resources :readings, only: :index, module: :sensors
  end

  # Configuration with chapters and surveys
  resource :configuration, only: :show do
    resources :chapters, only: %i[new create edit update destroy], module: :configurations
    resources :surveys, only: :show, module: :configurations
  end

  # Dashboard
  root 'dashboard#show'

  # Service management (RESTful nested resources)
  resources :services, only: [], module: :services do
    resource :row, only: :show
    resource :task, only: %i[create update destroy]

    collection do
      resource :batch, only: %i[create destroy]
    end
  end
end
