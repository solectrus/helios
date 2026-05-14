module Surveys
  module Senec
    class Survey < Base
      private

      def customize!(data)
        apply_image_choices!(data, :SENEC_COLLECTOR)
      end
    end
  end
end
