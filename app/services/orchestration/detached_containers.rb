module Orchestration
  # Removes the stopped containers of the project that hang in no Docker
  # network, so the `up` that follows builds them anew. Compose would start
  # such a container as it found it, and it would then resolve no service name
  # and wait for its dependencies forever.
  #
  # An interrupted `up` is what leaves one behind — see "Interrupted Stack
  # Starts" in docs/architecture/docker.md for how that happens and for what
  # the sweep deliberately spares.
  #
  # Removing the container costs nothing that matters: SOLECTRUS keeps its
  # data in bind mounts, so only the container layer goes.
  class DetachedContainers
    extend Loggable

    class << self
      def sweep
        # The list is cached for seconds and only the broadcast path refreshes
        # it. A container an `up` left behind moments ago is exactly what this
        # looks for, so ask Docker rather than the cache.
        Container.invalidate_cache

        detached = detached_containers
        return if detached.empty?

        detached.each { |container| remove(container) }
        Container.invalidate_cache
      end

      private

      # Removal goes by id, never by name. Docker frees a name the moment its
      # container goes, so by now the name can belong to a container someone
      # else built in the meantime — an id cannot be reused that way, which
      # turns a lost race into a no-op instead of the wrong container.
      def remove(container)
        success, output = DockerCli.force_remove_container(container.id)

        if success
          logger.warn("Removed #{container.name}: it hung in no network")
        else
          logger.warn("Could not remove #{container.name}: #{output.strip}")
        end
      end

      # Docker being unreachable is not this class's problem to report — the
      # compose command right after says it far better.
      def detached_containers
        Container.all.select { |container| detached?(container) }
      rescue ConnectionError, Docker::Error::DockerError => e
        logger.warn("Cannot check containers for missing networks: #{e.message}")
        []
      end

      # A running container is compose's to repair: it builds one anew the
      # moment an `up` covers it, and until then the container is at least
      # alive. Killing it here would leave nothing behind when the service
      # sits outside the dependency chain of that `up`.
      #
      # `host`, `none` and `container:` are deliberate network modes and carry
      # no network entry either, hence only a container that was meant to join
      # a named network counts as detached. An unreadable mode reads as
      # attached, so a container is never discarded on a value we cannot see.
      def detached?(container)
        return false if container.running?
        return false if protected?(container)
        return false unless networks(container).empty?

        mode = network_mode(container)
        mode.present? && %w[host none].exclude?(mode) &&
          !mode.start_with?('container:')
      end

      # HELIOS never starts its own service — every compose command leaves it
      # out — so an `up` could not rebuild its container anyway, and removing
      # it would take the interface away with no way back.
      #
      # A one-off container (`compose run`) belongs to no service the stack
      # keeps, and it sits unconnected for the moment between its creation and
      # its start.
      #
      # Both facts ride along on the container list, so neither costs an
      # inspect call.
      def protected?(container)
        container.service_name == Runner::SELF_SERVICE ||
          container.info.dig('Labels', COMPOSE_ONEOFF_LABEL) == 'True'
      end

      def networks(container)
        container.info.dig('NetworkSettings', 'Networks') || {}
      end

      def network_mode(container)
        container.info.dig('HostConfig', 'NetworkMode').to_s
      end
    end
  end
end
