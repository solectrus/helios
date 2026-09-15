module ApplicationHelper
  # Where the "Configuration" entry leads: the screen its warning sign marks,
  # or else the first screen of its sub-navigation, Sensors. A required
  # setting that is still empty comes first, because the stack cannot start
  # without it. An open data source comes next. In collectors_only mode the
  # Sensors screen is unreachable, so Data Sources is the entry there.
  def configuration_entry_path
    config = Configuration.current
    return settings_path if config.incomplete_required_settings?
    return datasources_path if config.incomplete_datasources? || config.collectors_only?

    sensors_path
  end
end
