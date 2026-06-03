module Import
  class ConfigurationImporter
    # Records the detected deployment mode. `full` is the implicit default and
    # stays absent so the section is empty until the user opens the deployment
    # card; `collectors_only` and `dashboard_only` are recorded explicitly.
    class DeploymentExtractor
      def initialize(mode:)
        @mode = mode
      end

      def section_data
        return nil if @mode == ConfigSchema::MODE_FULL

        { 'mode' => @mode }
      end
    end
  end
end
