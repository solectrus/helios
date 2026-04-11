Rails.application.routes.draw do
  # Health check with boot ID header for restart detection
  get 'up' => 'health#show', as: :rails_health_check

  # Restart status page
  resource :restarting, only: :show, controller: 'restarting'

  # Authentication
  resource :session, only: %i[new create destroy]

  # First-start consent
  resource :start, only: %i[show create]

  # Main navigation: configuration pages
  resource :sensors, only: :show
  get 'sensors/readings', to: 'sensors/readings#show', as: :sensors_readings
  resource :datasources, only: :show
  resource :advanced, only: :show, controller: 'advanced'

  # Setting CRUD (modal forms) — kept under 'configuration/' prefix for now
  scope 'configuration', as: :configuration do
    resources :settings, only: %i[new create], module: :configurations
    resources :surveys, only: :show, module: :configurations
  end

  scope 'configuration/:setting/:name',
        module: :configurations,
        constraints: { name: %r{[^/]+} } do
    get 'edit', to: 'settings#edit', as: :edit_configuration_setting
    patch '/', to: 'settings#update', as: :configuration_setting
    delete '/', to: 'settings#destroy'
  end

  # Service management
  resources :services, only: :index do
    resource :row, only: :show, module: :services
    resource :log, only: :show, module: :services
    resource :task, only: %i[create update destroy], module: :services
    resource :orphaned_task, only: :destroy, module: :services

    collection do
      resource :batch, only: %i[create destroy], module: :services
      resources :files, only: :show, module: :services
    end
  end

  root to: redirect('/services')
end
