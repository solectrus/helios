module Datasources
  class ShellyDevicesController < ApplicationController
    include TurboFrameOnly
    include InfluxNameValidation

    before_action :set_configuration
    before_action :require_turbo_frame, only: %i[new edit]
    before_action :load_device, only: %i[edit update destroy]

    def index
      @devices = @configuration.shelly_devices
    end

    def new
      render ShellyDeviceForm::Component.new
    end

    def edit
      render ShellyDeviceForm::Component.new(index: params[:id], data: @device)
    end

    def create
      data = device_params
      return unless data
      return if invalid_influx_name?(data, datasources_shelly_devices_path)

      @configuration.add_shelly_device(data)
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_shelly_devices_path
    end

    def update
      data = device_params
      return unless data
      return if invalid_influx_name?(data, datasources_shelly_devices_path)

      @configuration.update_shelly_device(params[:id], data)
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_shelly_devices_path
    end

    def destroy
      @configuration.remove_shelly_device(params[:id])
      Orchestration::StackStatus.mark_config_changed!
      redirect_to datasources_shelly_devices_path
    end

    private

    def set_configuration
      @configuration = Configuration.current
    end

    def load_device
      @device = @configuration.shelly_device(params[:id])
      redirect_to datasources_shelly_devices_path unless @device
    end

    def require_turbo_frame
      redirect_unless_turbo_frame(datasources_shelly_devices_path)
    end

    def device_params
      JSON.parse(params.require(:data))
    rescue JSON::ParserError
      head(:bad_request)
      nil
    end
  end
end
