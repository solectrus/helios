module Surveys
  module SystemNetwork
    class Survey < Base
      include AppHostField

      private

      # Never mandatory here. An installation that names no address is a state
      # of its own, and every caller falls back to the published port alone.
      # Where the address is the one thing that has to be there, behind an
      # external reverse proxy, the form that chooses that mode asks for it.
      def customize!(data)
        apply_app_host_validator!(data)

        # This form asks for the address of this machine, which is what the
        # address bar of the browser holds, so the field may be offered that
        # address. The reverse-proxy form carries the same field but asks a
        # different question, so it sets no marker. The browser reads it and
        # drops it before it builds the model (see survey_controller.ts).
        data['offerBrowserHost'] = true
      end
    end
  end
end
