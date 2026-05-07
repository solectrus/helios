module ConfigurationMigrations
  # Splits the single `influxdb.token` into the four role-specific fields in
  # `ConfigSchema::INFLUXDB_TOKEN_FIELDS`. Existing single-token installations
  # get all four populated with the same value — the running InfluxDB still
  # knows only one token, so collectors and dashboard keep authenticating.
  class SplitInfluxdbTokens < Base
    version 3

    def up(data)
      section = data['influxdb']
      return data unless section.is_a?(Hash)

      token = section.delete('token')
      return data if token.to_s.empty?

      ConfigSchema::INFLUXDB_TOKEN_FIELDS.each do |field|
        section[field] = token if section[field].to_s.empty?
      end
      data
    end
  end
end
