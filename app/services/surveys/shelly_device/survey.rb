module Surveys
  module ShellyDevice
    # Strips the identifier field that does not match the configured Shelly
    # connection mode — local devices are addressed by `host`, cloud devices
    # by `device_id`. The connection mode is set on the Shelly settings
    # card and is not part of the per-device form state, so we can't drive
    # the visibility from a SurveyJS `visibleIf` expression.
    class Survey < Base
      private

      def customize!(data)
        if Configuration.current.shelly_cloud?
          remove_element(data, 'host')
        else
          remove_element(data, 'device_id')
        end
      end

      def remove_element(data, name)
        data['pages']&.each do |page|
          page['elements']&.reject! { |element| element['name'] == name }
        end
      end
    end
  end
end
