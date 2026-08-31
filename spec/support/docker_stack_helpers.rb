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

  # Data paths emptied during the run. They must survive between examples (see
  # clear_data_path!), so the now-empty directories are removed once the suite
  # is over. Without this, a spec whose data path carries a random suffix
  # leaves one empty directory behind per run.
  CLEARED_PATHS = Set.new

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

  # Empties `data_path` but keeps the directory itself. Docker Desktop shares
  # the host directory into the VM by path: deleting it and creating it again
  # between two examples leaves the share pointing at the gone directory, and
  # the next `up` fails with "error while creating mount source path ...: no
  # such file or directory" even though the path exists on the host. Linux
  # binds the path directly and does not care, so this only ever failed
  # locally, never in CI.
  #
  # A plain rm_rf of the contents succeeds wherever the bind mount maps the
  # container's files to the host user (e.g. Docker Desktop). Only when files
  # survive — on Linux, where database files stay root-owned — fall back to
  # emptying the directory from inside a container. `cleanup_image` only needs
  # a `find` binary.
  def clear_data_path!(data_path, cleanup_image:)
    data_path = disposable!(data_path)
    CLEARED_PATHS << data_path
    delete_children(data_path)
    return if children_of(data_path).empty?

    system(
      'docker', 'run', '--rm', '--entrypoint', 'find',
      '-v', "#{data_path}:/cleanup", cleanup_image,
      '/cleanup', '-mindepth', '1', '-delete',
      out: File::NULL, err: File::NULL
    )
    delete_children(data_path)
  end

  private

  # Guards every deletion in this module. `data_path` reaches it from a spec's
  # `let`, and the fallbacks are bad: the test default of
  # `Rails.configuration.data_path` is `spec/fixtures` (all import scenarios),
  # the development one is `stack/` (the live local stack). A spec that forgets
  # to stub it, or stubs it too late, would hand one of those to rm_rf. Only a
  # path below `tmp/` is disposable, so anything else raises instead.
  def disposable!(data_path)
    resolved = File.expand_path(data_path.to_s)
    scratch = File.expand_path(Rails.root.join('tmp').to_s)
    return resolved if resolved.start_with?("#{scratch}/") && resolved != scratch

    raise ArgumentError,
          "refusing to clear #{resolved.inspect}: only paths below #{scratch}/ are disposable"
  end

  def delete_children(data_path)
    FileUtils.rm_rf(children_of(data_path))
  end

  def children_of(data_path)
    return [] unless Dir.exist?(data_path)

    Dir.children(data_path).map { |child| File.join(data_path, child) }
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

  config.after(:suite) do
    DockerStackHelpers::CLEARED_PATHS.each { |path| FileUtils.rm_rf(path) }
  end
end
