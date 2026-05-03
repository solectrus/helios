module SupportBundle
  module SystemInfo
    # Docker-side data for the support bundle: a single snapshot of the
    # daemon (info/version/containers) plus rendering of the Engine, Compose,
    # Containers and Networks sections derived from it.
    module DockerReport
      module_function

      def fetch_snapshot
        Orchestration::Connection.configure!
        {
          info: Docker.info,
          version: Docker.version,
          containers: Docker::Container.all(all: true),
        }
      rescue StandardError => e
        { error: "unavailable: #{e.class}: #{e.message}" }
      end

      def engine(docker)
        return { 'Status' => docker[:error] } if docker[:error]

        version = docker[:version]
        info = docker[:info]

        {
          'Version' => version['Version'],
          'API version' => version['ApiVersion'],
          'OS/Arch' => "#{version['Os']}/#{version['Arch']}",
          'Storage driver' => info['Driver'],
        }
      end

      def compose
        { 'Version' => OutputFormatter.capture('docker', 'compose', 'version', '--short') }
      end

      def containers(docker)
        return docker[:error] if docker[:error]

        list = docker[:containers]
        return 'No containers found.' if list.empty?

        [containers_summary(list), '', render_container_table(list)].join("\n")
      end

      # Service-name resolution between containers depends on every peer being
      # attached to the same Docker network. When that breaks (e.g. a container
      # was recreated outside the compose project, or networks were renamed),
      # peers fall back to host-only DNS, which fails. Listing membership here
      # makes the mismatch visible at a glance: the outlier sits in its own row.
      def networks(docker)
        return docker[:error] if docker[:error]

        list = docker[:containers]
        return 'No networks found.' if list.blank?

        membership = network_membership(list)
        return 'No networks found.' if membership.empty?

        rows = membership.sort.map { |name, names| [name, names.size.to_s, names.sort.join(', ')] }
        OutputFormatter.render_table(%w[NAME CONTAINERS NAMES], rows)
      end

      def network_membership(containers)
        containers.each_with_object(Hash.new { |h, k| h[k] = [] }) do |c, acc|
          networks = c.info.dig('NetworkSettings', 'Networks') || {}
          networks.each_key { |name| acc[name] << container_name(c) }
        end
      end

      def render_container_table(list)
        rows =
          list
          .sort_by { |c| [c.info['State'] == 'running' ? 0 : 1, container_name(c)] }
          .map { |c| container_row(c) }
        OutputFormatter.render_table(%w[NAME STATE STATUS IMAGE NETWORKS], rows)
      end

      def container_name(container)
        container.info['Names']&.first&.delete_prefix('/') ||
          container.info['Id'].to_s[0, 12]
      end

      def container_row(container)
        info = container.info
        [container_name(container), info['State'], info['Status'], info['Image'],
         container_networks(container).presence || '-']
      end

      def container_networks(container)
        networks = container.info.dig('NetworkSettings', 'Networks') || {}
        networks.keys.sort.join(',')
      end

      # Counting from the actual list we just fetched keeps the summary
      # consistent with the table below. /info's container counters can drift
      # on Docker Desktop/LinuxKit and report numbers that contradict the
      # real list, so we derive everything from one source.
      def containers_summary(list)
        running = list.count { |c| c.info['State'] == 'running' }
        "#{list.size} total (running: #{running}, stopped: #{list.size - running})"
      end
    end
  end
end
