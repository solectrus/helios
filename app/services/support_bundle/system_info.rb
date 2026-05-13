module SupportBundle
  # Collects a snapshot of the host environment (OS, CPU, memory, disk,
  # Docker) for inclusion in a support bundle. Each section is defensive:
  # if a command fails or a file is missing, its value degrades to a
  # short error line instead of aborting the whole report.
  #
  # The actual data collection lives in three sub-modules:
  # - HostMetrics: OS, CPU, memory, uptime, disk, data volumes
  # - DockerReport: engine, compose, containers, networks
  # - OutputFormatter: section/table rendering, capture, byte formatting
  module SystemInfo
    module_function

    def collect
      sections.map { |title, body| OutputFormatter.format_section(title, body) }.join("\n")
    end

    def sections
      docker = DockerReport.fetch_snapshot
      host_sections(docker).merge(docker_sections(docker)).merge(database_sections)
    end

    def host_sections(docker)
      {
        'HELIOS' => helios,
        'Operating System' => HostMetrics.operating_system(docker),
        'CPU' => HostMetrics.cpu,
        'Memory' => HostMetrics.memory(docker),
        'Uptime' => HostMetrics.uptime,
        'Disk' => HostMetrics.disk,
        'Data Volumes' => HostMetrics.data_volumes,
      }
    end

    def docker_sections(docker)
      {
        'Docker Engine' => DockerReport.engine(docker),
        'Docker Compose' => DockerReport.compose,
        'Docker Containers' => DockerReport.containers(docker),
        'Docker Networks' => DockerReport.networks(docker),
      }
    end

    def database_sections
      {
        'PostgreSQL Tables' => PostgresReport.tables,
        'InfluxDB' => InfluxReport.overview,
        'InfluxDB Measurements' => InfluxReport.measurements_list,
      }
    end

    def helios
      {
        'Version' => Rails.configuration.x.git.commit_version,
        'Commit time' => Rails.configuration.x.git.commit_time,
        'Collected at' => Time.current.iso8601,
      }
    end
  end
end
