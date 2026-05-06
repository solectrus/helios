module ConfigurationMigrations
  # Moves the deployment mode out of `system` into a dedicated `deployment`
  # section so the operating mode can be edited from its own card on the
  # configuration page.
  class ExtractDeploymentSection < Base
    version 2

    move 'mode', from: 'system', to: 'deployment'
  end
end
