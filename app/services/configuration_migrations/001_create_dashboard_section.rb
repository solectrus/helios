module ConfigurationMigrations
  # Moves dashboard-related fields out of `system` and `reverse_proxy` into a
  # dedicated `dashboard` section, matching the schema introduced together
  # with the dashboard configuration survey.
  class CreateDashboardSection < Base
    version 1

    move %w[co2_emission_factor frame_ancestors ui_theme lockup_codeword],
         from: 'system', to: 'dashboard'

    move 'trusted_proxy_ranges',
         from: 'reverse_proxy', to: 'dashboard'
  end
end
