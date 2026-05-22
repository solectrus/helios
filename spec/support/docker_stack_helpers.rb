# Lifecycle helpers shared by integration specs that drive a real Docker
# Compose stack rooted at a per-spec `data_path`.
module DockerStackHelpers
  # All stack-driving specs share one fixed Compose project name
  # (`Orchestration::PROJECT_NAME`), fixed container names and fixed host
  # ports — so two of them must never run concurrently, even though
  # `turbo_tests` spreads spec files across parallel workers. Specs tagged
  # `:docker_stack` grab this cross-process file lock for the duration of
  # each example, serialising stack access without serialising the rest of
  # the suite.
  STACK_LOCK_PATH = Rails.root.join('tmp/integration-docker-stack.lock').to_s

  def self.with_stack_lock
    File.open(STACK_LOCK_PATH, File::RDWR | File::CREAT, 0o644) do |lock|
      lock.flock(File::LOCK_EX)
      yield
    end
  end

  # Tears down the compose stack rooted at `data_path`. Idempotent — a no-op
  # when no compose file has been written yet (e.g. a clean first run).
  def compose_down!(data_path)
    return unless File.exist?(Compose.path)

    system(
      'docker', 'compose', '-f', Compose.path, '--project-directory', data_path,
      'down', '-v', '--remove-orphans',
      out: File::NULL, err: File::NULL
    )
  end

  # Removes `data_path`. A plain rm_rf succeeds wherever the bind mount maps
  # the container's files to the host user (e.g. Docker Desktop). Only when
  # files survive — on Linux, where database files stay root-owned — fall
  # back to emptying the directory from inside a container. `cleanup_image`
  # only needs a `find` binary.
  def remove_data_path!(data_path, cleanup_image:)
    FileUtils.rm_rf(data_path)
    return unless File.exist?(data_path)

    system(
      'docker', 'run', '--rm', '--entrypoint', 'find',
      '-v', "#{data_path}:/cleanup", cleanup_image,
      '/cleanup', '-mindepth', '1', '-delete',
      out: File::NULL, err: File::NULL
    )
    FileUtils.rm_rf(data_path)
  end
end

RSpec.configure do |config|
  config.include DockerStackHelpers

  # `around` wraps the example together with its before/after hooks, so the
  # lock spans the whole stack lifecycle (teardown of leftovers, start,
  # assertions, teardown).
  config.around(:each, :docker_stack) do |example|
    DockerStackHelpers.with_stack_lock { example.run }
  end
end
