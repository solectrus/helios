require 'open3'

module Orchestration
  # Garbage-collects Docker images left behind after lifecycle operations
  # (see Runner.up / Runner.recreate). Stopped services are intentionally
  # skipped — the user may still need their images. We never pass --force, so
  # any image still referenced by a container survives.
  class ImageCleanup
    class << self
      def run(previous_image: nil)
        prune_images(previous_image) if previous_image.present?
        prune_legacy_for_running_services
        prune_dangling_images
      end

      private

      def prune_images(*images)
        return if images.empty?

        Open3.capture2e('docker', 'image', 'rm', *images)
      end

      def prune_legacy_for_running_services
        Orchestration::Container.invalidate_cache
        running = Orchestration::Container.all.select(&:running?)
        in_use = running.map(&:image)
        tags = running.flat_map { |c| known_tags_for(c.service_name) }.uniq - in_use
        prune_images(*tags)
      end

      def known_tags_for(service_name)
        DockerImages.known_for(service_name).flat_map do |entry|
          entry.include?(':') ? [entry] : tags_for_repo(entry)
        end
      end

      def tags_for_repo(repo)
        output, status =
          Open3.capture2e('docker', 'images', repo, '--format', '{{.Repository}}:{{.Tag}}')
        return [] unless status.success?

        output.lines.map(&:strip).reject { |line| line.empty? || line.end_with?(':<none>') }
      end

      def prune_dangling_images
        Open3.capture2e('docker', 'image', 'prune', '-f')
      end
    end
  end
end
