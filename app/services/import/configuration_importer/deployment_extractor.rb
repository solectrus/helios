module Import
  class ConfigurationImporter
    # Detects the deployment mode of an existing installation. Only
    # `collectors_only` is recorded — `full` is the implicit default and stays
    # absent so the section is empty until the user opens the deployment card.
    class DeploymentExtractor
      def initialize(collectors_only:)
        @collectors_only = collectors_only
      end

      def section_data
        return nil unless @collectors_only

        { 'mode' => ConfigSchema::MODE_COLLECTORS_ONLY }
      end
    end
  end
end
