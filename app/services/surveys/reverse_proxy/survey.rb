module Surveys
  module ReverseProxy
    class Survey < Base
      include AppHostField

      private

      def customize!(data)
        apply_app_host_validator!(data)
      end
    end
  end
end
