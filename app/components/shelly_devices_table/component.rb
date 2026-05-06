module ShellyDevicesTable
  class Component < ViewComponent::Base
    attr_reader :devices, :configuration

    delegate :empty?, to: :devices

    def initialize(devices:, configuration:)
      super()
      @devices = devices
      @configuration = configuration
    end

    def identifier_field
      configuration.shelly_cloud? ? 'device_id' : 'host'
    end

    def identifier_label
      t("datasources.shelly_devices.table.#{identifier_field}")
    end

    def identifier_for(device)
      device[identifier_field]
    end
  end
end
