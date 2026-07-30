# Real PostgreSQL major-version upgrade against Docker — no mocking of the
# Docker layer. Builds a HELIOS stack with PostgreSQL on an older major,
# starts it, writes data, and runs the actual upgrade and rollback paths.
#
# Tagged :integration by its spec/integration/ location: it always runs on
# CI and is skipped in local runs unless requested with `--tag integration`.
# Also skipped when Docker is unavailable. Slow: it pulls PostgreSQL images
# and runs initdb several times.
require 'tmpdir'

RSpec.describe Orchestration::PostgresqlUpgrade, :docker_stack do
  let(:data_path) { Rails.root.join('tmp/pg-upgrade-itest').to_s }
  let(:starting_image) { 'postgres:17-alpine' }

  before do
    skip_without_docker

    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    write_config!
    Export::Builder.new(Configuration.current).write!
    compose_down!(data_path) # clear any leftovers from a previous interrupted run
  end

  after do
    compose_down!(data_path)
    remove_data_path!(data_path, cleanup_image: starting_image)
  end

  describe '.call (real major-version upgrade)' do
    it 'migrates the database to the new major with data intact' do
      Orchestration::Runner.start('postgresql')
      container = wait_until_ready!
      expect(described_class.current_major(container)).to eq(17)
      seed_data!

      expect(described_class.call).to be true

      upgraded = wait_until_ready!
      aggregate_failures do
        expect(described_class.current_major(upgraded)).to eq(described_class.target_major)
        expect(widget_names).to eq(['helios'])
        expect(Configuration.current.postgresql.image).to eq(described_class.target_image)
        expect(Dir.glob(File.join(data_path, 'postgresql-upgrade-*.sql'))).to be_empty
      end
    end

    # Reproduces the field incident: a stack imported from legacy SOLECTRUS,
    # where the database service was named `db`. After the upgrade renames it to
    # `postgresql`, the old container lingers as a crash-looping orphan unless
    # the upgrade's reconcile prunes it (--remove-orphans). Before the fix the
    # orphan survived and only a full host reboot cleaned it up.
    it 'prunes the orphan left by a former database service name' do
      Orchestration::Runner.start('postgresql')
      wait_until_ready!
      seed_data!

      start_orphan!('db')
      expect(project_service_names).to include('db')

      expect(described_class.call).to be true

      wait_until_ready!
      aggregate_failures do
        expect(project_service_names).to include('postgresql')
        expect(project_service_names).not_to include('db')
        expect(widget_names).to eq(['helios'])
      end
    end
  end

  describe '#call (rollback when the migration fails)' do
    it 'returns to the previous major with data intact' do
      Orchestration::Runner.start('postgresql')
      container = wait_until_ready!
      expect(described_class.current_major(container)).to eq(17)
      seed_data!

      # Fail after the dump has been restored into the new major, so the
      # rollback has to rebuild the old cluster from the dump.
      upgrade = described_class.new
      allow(upgrade).to receive(:verify_restore!)
        .and_raise(described_class::UpgradeError, 'simulated verification failure')

      expect { upgrade.call }.to raise_error(
        described_class::UpgradeError, /rolled back|zurückgesetzt/
      )

      restored = wait_until_ready!
      expect(described_class.current_major(restored)).to eq(17)
      expect(widget_names).to eq(['helios'])
      expect(Configuration.current.postgresql.image).to eq(starting_image)
    end
  end

  describe '#call (rollback before the data directory is touched)' do
    it 'reverts the image and leaves the running cluster untouched' do
      Orchestration::Runner.start('postgresql')
      container = wait_until_ready!
      expect(described_class.current_major(container)).to eq(17)
      seed_data!

      # Fail inside bump_image!, before the destructive phase begins. The
      # live cluster must keep running on its original files — no wipe, no
      # rebuild from the dump.
      allow(Orchestration::Runner).to receive(:pull)
        .and_raise(Orchestration::Runner::CommandError, 'simulated pull failure')

      expect { described_class.call }.to raise_error(
        described_class::UpgradeError, /rolled back|zurückgesetzt/
      )

      restored = wait_until_ready!
      expect(described_class.current_major(restored)).to eq(17)
      expect(widget_names).to eq(['helios'])
      expect(Configuration.current.postgresql.image).to eq(starting_image)
    end
  end

  # --- helpers ---

  # Builds a known-good HELIOS configuration (a real fixture stack) pinned to
  # the older PostgreSQL major, so Export::Builder produces a valid stack.
  def write_config!
    source = Rails.root.join('spec/fixtures/import_scenarios/with_ingest/helios/config.yaml')
    data = YAML.safe_load_file(source, permitted_classes: [Date])
    data['postgresql']['image'] = starting_image

    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump(data))
  end

  # Mirrors a real stack: the postgres image creates `solectrus` from
  # POSTGRES_DB and leaves it empty, while SOLECTRUS itself works in
  # `solectrus_production`. Seeding there is what makes the upgrade's own
  # table-count verification (PostgresqlUpgrade::DATABASE) meaningful — against
  # the empty `solectrus` it would compare 0 to 0 and pass no matter what.
  def seed_data!
    run_sql!("CREATE DATABASE #{described_class::DATABASE}", database: 'solectrus')
    run_sql!('CREATE TABLE widgets (id serial PRIMARY KEY, name text)')
    run_sql!("INSERT INTO widgets (name) VALUES ('helios')")
  end

  # Starts a container that mimics a leftover from a previously named database
  # service. Created through Docker Compose (a throwaway one-service file under
  # the same project name) so it carries the full label set Compose uses for
  # orphan detection — a `docker run` container with only a subset is not
  # recognized as an orphan. Reuses the already-pulled starting_image, and
  # network_mode: none avoids creating a stray project network.
  def start_orphan!(service)
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'orphan-compose.yaml')
      File.write(file, <<~YAML)
        name: #{Orchestration::PROJECT_NAME}
        services:
          #{service}:
            image: #{starting_image}
            entrypoint: ["sleep", "300"]
            network_mode: none
      YAML
      system(
        'docker', 'compose', '-f', file, '--project-directory', data_path,
        'up', '--no-build', '-d', service,
        out: File::NULL, err: File::NULL
      ) or raise "failed to start orphan service #{service}"
    end
  end

  def project_service_names
    format = '{{.Label "com.docker.compose.service"}}'
    `docker ps -a --filter label=com.docker.compose.project=#{Orchestration::PROJECT_NAME} --format '#{format}'`
      .split("\n").map(&:strip).reject(&:empty?)
  end

  def widget_names
    stdout, stderr, code = psql('-tAc', 'SELECT name FROM widgets ORDER BY id')
    raise "querying widgets failed: #{stderr}" unless code&.zero?

    stdout.split("\n").map(&:strip)
  end

  def run_sql!(sql, database: described_class::DATABASE)
    _stdout, stderr, code = psql('-c', sql, database:)
    raise "SQL failed (#{sql}): #{stderr}" unless code&.zero?
  end

  def psql(*, database: described_class::DATABASE)
    Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-d', database, *
    )
  end

  # Waits until PostgreSQL truly accepts connections — not just until Docker
  # reports the container healthy.
  #
  # On a first-time start the postgres image runs a temporary bootstrap server
  # that listens on the Unix socket only (`listen_addresses=''`). The container
  # healthcheck (`pg_isready` over that socket) can flip to "healthy" against
  # the throwaway server, then the bootstrap server shuts down — so a query
  # racing it dies with "terminating connection due to administrator command".
  # A TCP probe stays negative until the real server is up, mirroring
  # Orchestration::PostgresqlUpgrade#accepting_tcp_connections?.
  def wait_until_ready!(timeout: 120)
    deadline = Time.current + timeout

    loop do
      Orchestration::Container.invalidate_cache
      container = Orchestration::Container.find('postgresql')
      return container if container&.healthy? && accepting_tcp_connections?
      raise "PostgreSQL did not become ready within #{timeout}s" if Time.current > deadline

      sleep 1
    end
  end

  def accepting_tcp_connections?
    _stdout, _stderr, code =
      Orchestration::Runner.compose_exec(
        'postgresql', 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q'
      )
    code&.zero?
  end
end
