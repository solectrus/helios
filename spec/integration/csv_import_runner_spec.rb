# End-to-end coverage of the CSV import path: HELIOS launches the real
# csv-importer image against a live InfluxDB and Postgres stack, then
# the completion thread flushes Redis and runs a scoped DELETE on the
# `summaries` table — only the days the SENEC weekly file covers (week
# 22/2026 → Mon 25.05.2026..Sun 31.05.2026) are removed, a row outside
# that range stays cached.
#
# Tagged :integration by its spec/integration/ location. Slow: pulls
# Postgres, InfluxDB, Redis and csv-importer images, runs a real
# import.
RSpec.describe CsvImportRunner, :docker_stack do
  let(:data_path) { Rails.root.join("tmp/csv-import-itest#{ENV.fetch('TEST_ENV_NUMBER', nil)}").to_s }
  let(:in_range_date) { Date.new(2026, 5, 27) } # within ISO week 22/2026
  let(:out_of_range_date) { Date.new(2026, 4, 1) } # well before

  before do
    skip_without_docker

    allow(Rails.configuration).to receive(:data_path).and_return(data_path)
    FileUtils.mkdir_p(data_path)
    write_config!
    Export::Builder.new(Configuration.current).write!
    align_write_token_with_admin!
    compose_down!(data_path) # clear leftovers from a previous interrupted run

    # CsvImportRunner spawns threads for prep + completion; run them
    # inline so the test waits on a single synchronous chain.
    allow(described_class).to receive(:spawn_preparing_thread!) do |instance|
      instance.send(:run_preparing!)
    end
    allow(described_class).to receive(:spawn_completion_thread!) do |raw|
      described_class.new.process_completion!(raw)
    end
  end

  after do
    compose_down!(data_path)
    clear_data_path!(data_path, cleanup_image: described_class::IMAGE)
  end

  describe '.start (real csv-importer against a live stack)' do
    it 'imports a SENEC weekly export and scopes the summaries reset to its 7 days' do
      bring_stack_up!
      seed_summaries!
      stage_senec_csv!('S123-week-22-2026.csv')

      described_class.start
      wait_for_container_exit!(described_class::CONTAINER_NAME, timeout: 360)
      described_class.detect_completion!

      aggregate_failures do
        expect(described_class.error_message).to be_nil,
                                                 "import failed: #{described_class.error_message}"
        expect(described_class.success_message).to eq('1')
        expect(remaining_summary_dates).to eq([out_of_range_date])
        expect(File).not_to exist(CsvImportUploader.extract_directory)
        expect(File).not_to exist(CsvImportUploader.upload_path)
      end
    end
  end

  # --- helpers ---

  def bring_stack_up!
    Orchestration::Runner.start('postgresql', 'influxdb', 'redis')
    wait_for_postgresql_ready!
    wait_for_healthy!('influxdb')
    wait_for_healthy!('redis')
  end

  def seed_summaries!
    create_production_database!
    create_summaries_table!
    seed_summary_row!(in_range_date)
    seed_summary_row!(out_of_range_date)
  end

  # Minimal HELIOS configuration — Export::Builder.ensure_defaults!
  # materializes postgresql, influxdb, redis, dashboard with passwords,
  # tokens and images. No publish_port, so the stack does not clash
  # with other dev containers.
  def write_config!
    FileUtils.mkdir_p(File.dirname(Configuration.path))
    File.write(Configuration.path, YAML.dump({}))
    Current.reset
  end

  # ensure_defaults! gives every InfluxDB token its own random value,
  # but the InfluxDB image only registers the admin token on first
  # bootstrap. Aligning INFLUX_TOKEN_WRITE with the admin token lets
  # the csv-importer write straight away, without an extra `influx
  # auth create` step.
  def align_write_token_with_admin!
    env_path = File.join(data_path, '.env')
    contents = File.read(env_path)
    admin_token = contents[/^INFLUX_ADMIN_TOKEN=(.+)$/, 1]
    raise 'INFLUX_ADMIN_TOKEN missing from generated .env' unless admin_token

    File.write(env_path, contents.sub(/^INFLUX_TOKEN_WRITE=.+$/, "INFLUX_TOKEN_WRITE=#{admin_token}"))
  end

  # `summaries` lives in the SOLECTRUS schema; for the scoped-reset test
  # we only care about its primary key. Mirroring the production schema
  # would couple this spec to migrations we don't ship.
  def create_summaries_table!
    psql_in_production!('CREATE TABLE summaries (date date PRIMARY KEY)')
  end

  def seed_summary_row!(date)
    psql_in_production!("INSERT INTO summaries (date) VALUES ('#{date.iso8601}')")
  end

  def remaining_summary_dates
    stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-d', 'solectrus_production',
      '-tAc', 'SELECT date FROM summaries ORDER BY date'
    )
    raise "summaries query failed: #{stderr}" unless code&.zero?

    stdout.split("\n").map(&:strip).reject(&:empty?).map { |s| Date.parse(s) }
  end

  # Real SENEC weekly export header (10 columns, including the battery
  # voltage/current/SoC trio) verbatim from a 2026 mein-senec.de export.
  # The csv-importer probe keys off the literal `Uhrzeit;Netzbezug [kW]`
  # prefix. Two rows on Mon 25.05.2026 anchor the file inside ISO week
  # 22/2026 — enough for the scoped DELETE assertion.
  def stage_senec_csv!(basename)
    FileUtils.mkdir_p(CsvImportUploader.extract_directory)
    File.write(File.join(CsvImportUploader.extract_directory, basename), <<~CSV)
      Uhrzeit;Netzbezug [kW];Netzeinspeisung [kW];Stromverbrauch [kW];Akkubeladung [kW];Akkuentnahme [kW];Stromerzeugung [kW];Akku Spannung [V];Akku Stromstärke [A];Akku Füllstand [%]
      25.05.2026 00:01:38;0;0;0;0;0;0;0;0;0
      25.05.2026 00:06:40;0,162976;0;0,162976;0;0;0;0;0;0
    CSV
  end

  def create_production_database!
    _stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-c', 'CREATE DATABASE solectrus_production'
    )
    raise "creating solectrus_production failed: #{stderr}" unless code&.zero?
  end

  def psql_in_production!(sql)
    _stdout, stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'psql', '-U', 'postgres', '-d', 'solectrus_production', '-c', sql
    )
    raise "SQL failed (#{sql}): #{stderr}" unless code&.zero?
  end

  def wait_for_healthy!(service, timeout: 180)
    deadline = Time.current + timeout

    loop do
      Orchestration::Container.invalidate_cache
      container = Orchestration::Container.find(service)
      return container if container&.healthy?
      if Time.current > deadline
        raise "#{service} did not become healthy within #{timeout}s\n#{healthy_diagnostics(service)}"
      end

      sleep 2
    end
  end

  # See restore_runner_spec for the bootstrap-server race rationale.
  def wait_for_postgresql_ready!(timeout: 180)
    wait_for_healthy!('postgresql', timeout:)
    deadline = Time.current + timeout

    until postgresql_accepting_tcp_connections?
      raise "postgresql did not accept TCP connections within #{timeout}s" if Time.current > deadline

      sleep 1
    end
  end

  def postgresql_accepting_tcp_connections?
    _stdout, _stderr, code = Orchestration::Runner.compose_exec(
      'postgresql', 'pg_isready', '-h', '127.0.0.1', '-U', 'postgres', '-q'
    )
    code&.zero?
  end

  # CsvImportRunner intentionally does NOT use `--rm`, so the
  # container lingers in `docker ps -a` after exit (process_completion!
  # removes it). Wait on the State.Running flag from inspect instead.
  def wait_for_container_exit!(name, timeout: 240)
    deadline = Time.current + timeout
    until Time.current > deadline
      raw = Orchestration::DockerCli.inspect_container(name)
      return true if raw && !raw.dig('State', 'Running')

      sleep 0.5
    end
    raise "#{name} did not exit within #{timeout}s\n#{container_diagnostics(name)}"
  end

  def container_diagnostics(name)
    logs, = Open3.capture2e('docker', 'logs', '--tail', '40', name)
    "--- #{name} logs ---\n#{logs}"
  end

  def healthy_diagnostics(service)
    container = Orchestration::Container.find(service)
    state =
      if container
        "status=#{container.status} health=#{container.health_status.inspect}"
      else
        'container not found'
      end
    ps, = Open3.capture2e('docker', 'ps', '-a')
    logs, = container ? Open3.capture2e('docker', 'logs', '--tail', '40', container.name) : ['', nil]
    "[#{service}] #{state}\n--- docker ps -a ---\n#{ps}\n--- #{service} logs ---\n#{logs}"
  end
end
