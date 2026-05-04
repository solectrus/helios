module Import
  class ConfigurationImporter
    class ReverseProxyExtractor
      include Helpers

      def initialize(reader, volume_resolver)
        @reader = reader
        @volume_resolver = volume_resolver
      end

      def section_data
        return nil unless @reader.services.key?('traefik')

        domain = extract_domain_from_dashboard_labels
        return nil unless domain

        {
          'app_domain' => domain,
          'letsencrypt_email' => @reader.raw_env['LETSENCRYPT_EMAIL'],
        }.merge(@volume_resolver.path_data('reverse_proxy')).compact.presence
      end

      private

      def extract_domain_from_dashboard_labels
        rule_value = find_traefik_rule_label
        match = rule_value&.match(/Host\(`([^`]+)`\)/)
        match && match[1]
      end

      def find_traefik_rule_label
        labels = @reader.service('dashboard')&.dig('labels') || {}

        if labels.is_a?(Hash)
          labels.find { |k, _| k.include?('routers.dashboard.rule') }&.last
        else
          labels.find { |v| v.to_s.include?('routers.dashboard.rule') }
        end
      end
    end
  end
end
