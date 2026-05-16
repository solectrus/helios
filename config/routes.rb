Rails.application.routes.draw do
  # Health check with boot ID header for restart detection
  get 'up' => 'health#show', as: :rails_health_check

  # Restart status page
  resource :restarting, only: :show, controller: 'restarting'

  # Authentication
  resource :session, only: %i[new create destroy]

  # First-start consent
  resource :start, only: %i[show create]

  resource :sensors, only: :show do
    resource :readings, only: :show, module: :sensors
  end
  resource :datasources, only: :show do
    scope module: :datasources do
      namespace :mqtt_topics, path: 'mqtt-topics' do
        resource :readings, only: :show
      end
      resources :mqtt_topics,
                only: %i[index new create edit update destroy],
                path: 'mqtt-topics'
      resources :shelly_devices,
                only: %i[index new create edit update destroy],
                path: 'shelly-devices'
    end
  end
  resource :advanced, only: :show, controller: 'advanced'
  resource :host_stats, only: :show, path: 'host-stats'
  resource :status_bar, only: :show, path: 'status-bar'
  scope 'backups', module: :backups, as: :backups do
    resource :failure, only: :destroy
    resource :restore_failure, only: :destroy
    resource :upload, only: :create
  end
  resources :backups,
            only: %i[index create show destroy],
            controller: 'backups/backups' do
    resource :restore, only: :create, module: :backups
  end
  resource :support, only: %i[new create]

  scope 'configuration', as: :configuration do
    resources :settings, only: %i[new create], module: :configurations
    resources :surveys, only: :show, module: :configurations
    resource :reset, only: %i[create destroy], module: :configurations
    resource :connection_test, only: :create, module: :configurations
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
    resource :image, only: :update, module: :services
    resource :orphaned_task, only: :destroy, module: :services

    collection do
      resource :batch, only: %i[create destroy], module: :services
      resources :files, only: :show, module: :services
    end
  end

  root to: redirect('/services')
end
