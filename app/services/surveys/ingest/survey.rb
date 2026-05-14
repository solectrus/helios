module Surveys
  module Ingest
    class Survey < Base
      private

      def customize!(data)
        apply_image_choices!(data, :INGEST)
      end
    end
  end
end
