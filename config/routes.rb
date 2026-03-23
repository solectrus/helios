Rails.application.routes.draw do
  # Health check
  get 'up' => 'rails/health#show', :as => :rails_health_check

  # Authentication
  resource :session, only: %i[new create destroy]

  # Generated files preview
  resource :generated_files, only: :show

  # Configuration with settings and surveys
  resource :configuration, only: :show do
    resources :settings, only: %i[new create], module: :configurations
    resources :surveys, only: :show, module: :configurations
    resources :readings, only: :index, module: :configurations
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

    collection do
      resource :batch, only: %i[create destroy], module: :services
    end
  end

  root to: redirect('/services')
end
