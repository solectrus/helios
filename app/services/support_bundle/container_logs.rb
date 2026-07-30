module SupportBundle
  # Captures the last N lines of logs for every container in the HELIOS
  # compose project. Uses `docker logs` (via Open3) to get plain text —
  # bypasses the Docker multiplex stream protocol and works for stopped
  # containers too.
  module ContainerLogs
    TAIL_LINES = 500

    module_function

    def collect
      Orchestration::Container.all.to_h do |container|
        [filename_for(container), fetch_log(container.id)]
      end
    rescue Orchestration::ConnectionError => e
      { 'logs/_error.txt' => "Docker unavailable: #{e.message}\n" }
    end

    def filename_for(container)
      name = container.service_name.presence || container.name.presence || container.id[0, 12]
      "logs/#{name.gsub(/[^A-Za-z0-9._-]/, '_')}.log"
    end

    def fetch_log(container_id)
      output, status = Open3.capture2e(
        'docker', 'logs', '--tail', TAIL_LINES.to_s, '--timestamps', container_id
      )
      # Services log in whatever encoding they please; anonymizing invalid
      # UTF-8 would raise and take the whole bundle down.
      output = TextEncoding.utf8(output)
      return output if status.success?

      "failed (exit #{status.exitstatus}):\n#{output}"
    rescue StandardError => e
      "unavailable: #{e.class}: #{e.message}\n"
    end
  end
end
