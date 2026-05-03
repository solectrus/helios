module Export
  class Env
    class Ingest < Section
      def call
        env.add_section('Ingest (recalculates house_power for balcony power plants)')

        entry('RETENTION_HOURS', configuration.ingest.retention_hours.presence || '12',
              'Hours of measurement data Ingest buffers in its SQLite store')
        volume_path_entry(Services::Ingest, 'Ingest data')
      end
    end
  end
end
