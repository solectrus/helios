module Surveys
  module DashboardGeocoding
    # The form asks the three states of `nominatim_url` (see
    # ConfigSchema::DASHBOARD_FIELDS) as a `nominatim` choice, which is never
    # stored. The two methods translate between them.
    class Survey < Base
      def self.choice(url)
        return 'public' if url.nil?

        url.empty? ? 'off' : 'custom'
      end

      # nil for the public server, so the field is not stored at all
      def self.url(choice, url)
        case choice
        when 'off' then ''
        when 'custom' then url.to_s.strip
        end
      end
    end
  end
end
