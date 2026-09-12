module ConfigurationMigrations
  # Writes down the Ingest decision that used to be implicit.
  #
  # Until now HELIOS skipped Ingest whenever one of its inputs came from a
  # source it does not manage: it could not reroute such a source, so it left
  # the house-power correction to the external side. Ingest now accepts those
  # sources on its own write endpoint, and a switch (`ingest.active`, default
  # on) decides whether the correction runs.
  #
  # An existing configuration carries no switch, and the new default would read
  # the missing value as "on". That is the wrong reading: the user was never
  # asked, and the answer HELIOS gave on their behalf was "off". Turning it on
  # unasked would export Ingest, point every managed collector at it, and wait
  # for a value the external source still writes straight to InfluxDB. Ingest
  # computes only for a moment in which every configured sensor has a value, so
  # house_power would stop being written at all.
  #
  # So the old answer is persisted as `active: false`. The Ingest card is
  # visible either way, and switching the correction on there names the address
  # the external source has to write to.
  class PreserveIngestOffForExternal < Base
    version 5

    def up(data)
      return data unless sensors_normalized?(data)

      configuration = Configuration.from_data(data)
      return data unless configuration.ingest_offered? && configuration.external_ingest_inputs.any?

      (data['ingest'] ||= {})['active'] = false
      data
    end

    private

    # Sensor values are hashes in every file HELIOS has written; a raw
    # "MEASUREMENT:field" string only appears mid-import, where no migration
    # runs. Reading one would raise, and a migration must never keep the app
    # from booting, so an unexpected shape leaves the data alone.
    def sensors_normalized?(data)
      sensors = data['sensors']
      sensors.nil? || (sensors.is_a?(Hash) && sensors.each_value.all?(Hash))
    end
  end
end
