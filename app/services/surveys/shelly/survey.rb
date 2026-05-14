module Surveys
  module Shelly
    class Survey < Base
      private

      def customize!(data)
        apply_image_choices!(data, :SHELLY_COLLECTOR)
      end
    end
  end
end
