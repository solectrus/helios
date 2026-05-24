# == Route Map
#
#                            Prefix Verb   URI Pattern                                    Controller#Action
#                rails_health_check GET    /up(.:format)                                  health#show
#                        restarting GET    /restarting(.:format)                          restarting#show
#                       new_session GET    /session/new(.:format)                         sessions#new
#                           session DELETE /session(.:format)                             sessions#destroy
#                                   POST   /session(.:format)                             sessions#create
#                             start GET    /start(.:format)                               starts#show
#                                   POST   /start(.:format)                               starts#create
#                  sensors_readings GET    /sensors/readings(.:format)                    sensors/readings#show
#                           sensors GET    /sensors(.:format)                             sensors#show
#  datasources_mqtt_topics_readings GET    /datasources/mqtt-topics/readings(.:format)    datasources/mqtt_topics/readings#show
#           datasources_mqtt_topics GET    /datasources/mqtt-topics(.:format)             datasources/mqtt_topics#index
#                                   POST   /datasources/mqtt-topics(.:format)             datasources/mqtt_topics#create
#        new_datasources_mqtt_topic GET    /datasources/mqtt-topics/new(.:format)         datasources/mqtt_topics#new
#       edit_datasources_mqtt_topic GET    /datasources/mqtt-topics/:id/edit(.:format)    datasources/mqtt_topics#edit
#            datasources_mqtt_topic PATCH  /datasources/mqtt-topics/:id(.:format)         datasources/mqtt_topics#update
#                                   PUT    /datasources/mqtt-topics/:id(.:format)         datasources/mqtt_topics#update
#                                   DELETE /datasources/mqtt-topics/:id(.:format)         datasources/mqtt_topics#destroy
#        datasources_shelly_devices GET    /datasources/shelly-devices(.:format)          datasources/shelly_devices#index
#                                   POST   /datasources/shelly-devices(.:format)          datasources/shelly_devices#create
#     new_datasources_shelly_device GET    /datasources/shelly-devices/new(.:format)      datasources/shelly_devices#new
#    edit_datasources_shelly_device GET    /datasources/shelly-devices/:id/edit(.:format) datasources/shelly_devices#edit
#         datasources_shelly_device PATCH  /datasources/shelly-devices/:id(.:format)      datasources/shelly_devices#update
#                                   PUT    /datasources/shelly-devices/:id(.:format)      datasources/shelly_devices#update
#                                   DELETE /datasources/shelly-devices/:id(.:format)      datasources/shelly_devices#destroy
#                       datasources GET    /datasources(.:format)                         datasources#show
#                          advanced GET    /advanced(.:format)                            advanced#show
#                        host_stats GET    /host-stats(.:format)                          host_stats#show
#                        status_bar GET    /status-bar(.:format)                          status_bars#show
#                   backups_failure DELETE /backups/failure(.:format)                     backups/failures#destroy
#           backups_restore_failure DELETE /backups/restore_failure(.:format)             backups/restore_failures#destroy
#                    backups_upload POST   /backups/upload(.:format)                      backups/uploads#create
#                    backup_restore POST   /backups/:backup_id/restore(.:format)          backups/restores#create
#                           backups GET    /backups(.:format)                             backups/backups#index
#                                   POST   /backups(.:format)                             backups/backups#create
#                            backup GET    /backups/:id(.:format)                         backups/backups#show
#                                   DELETE /backups/:id(.:format)                         backups/backups#destroy
#                       new_support GET    /support/new(.:format)                         supports#new
#                           support POST   /support(.:format)                             supports#create
#            configuration_settings POST   /configuration/settings(.:format)              configurations/settings#create
#         new_configuration_setting GET    /configuration/settings/new(.:format)          configurations/settings#new
#              configuration_survey GET    /configuration/surveys/:id(.:format)           configurations/surveys#show
#               configuration_reset DELETE /configuration/reset(.:format)                 configurations/resets#destroy
#                                   POST   /configuration/reset(.:format)                 configurations/resets#create
#     configuration_connection_test POST   /configuration/connection_test(.:format)       configurations/connection_tests#create
#        edit_configuration_setting GET    /configuration/:setting/:name/edit(.:format)   configurations/settings#edit {name: /[^\/]+/}
#             configuration_setting PATCH  /configuration/:setting/:name(.:format)        configurations/settings#update {name: /[^\/]+/}
#                                   DELETE /configuration/:setting/:name(.:format)        configurations/settings#destroy {name: /[^\/]+/}
#                       service_row GET    /services/:service_id/row(.:format)            services/rows#show
#                       service_log GET    /services/:service_id/log(.:format)            services/logs#show
#                      service_task PATCH  /services/:service_id/task(.:format)           services/tasks#update
#                                   PUT    /services/:service_id/task(.:format)           services/tasks#update
#                                   DELETE /services/:service_id/task(.:format)           services/tasks#destroy
#                                   POST   /services/:service_id/task(.:format)           services/tasks#create
#                     service_cache DELETE /services/:service_id/cache(.:format)          services/caches#destroy
#                   service_upgrade POST   /services/:service_id/upgrade(.:format)        services/upgrades#create
#                     service_image PATCH  /services/:service_id/image(.:format)          services/images#update
#                                   PUT    /services/:service_id/image(.:format)          services/images#update
#             service_orphaned_task DELETE /services/:service_id/orphaned_task(.:format)  services/orphaned_tasks#destroy
#                             batch DELETE /services/batch(.:format)                      services/batches#destroy
#                                   POST   /services/batch(.:format)                      services/batches#create
#                              file GET    /services/files/:id(.:format)                  services/files#show
#                          services GET    /services(.:format)                            services#index
#                              root GET    /                                              redirect(301, /services)
#  turbo_recede_historical_location GET    /recede_historical_location(.:format)          turbo/native/navigation#recede
#  turbo_resume_historical_location GET    /resume_historical_location(.:format)          turbo/native/navigation#resume
# turbo_refresh_historical_location GET    /refresh_historical_location(.:format)         turbo/native/navigation#refresh

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
  resource :about, only: :show, controller: 'about' do
    scope module: :about do
      resource :component, only: :show
    end
  end

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
    resource :cache, only: :destroy, module: :services
    resource :upgrade, only: :create, module: :services
    resource :image, only: :update, module: :services
    resource :orphaned_task, only: :destroy, module: :services

    collection do
      resource :batch, only: %i[create destroy], module: :services
      resources :files, only: :show, module: :services
    end
  end

  root to: redirect('/services')
end
