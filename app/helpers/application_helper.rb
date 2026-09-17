module ApplicationHelper
  # Where the "Configuration" entry leads: the screen its warning sign marks,
  # or else the first screen of its sub-navigation, Sensors. Only a data source
  # can be open, so it comes first. In collectors_only mode the Sensors screen
  # is unreachable, so Data Sources is the entry there too.
  def configuration_entry_path
    config = Configuration.current
    return datasources_path if config.incomplete_datasources? || config.collectors_only?

    sensors_path
  end
end
