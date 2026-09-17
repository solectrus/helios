# The snapshot of a scenario: the `compose.yaml`, `.env` and `config.yaml`
# that HELIOS produced for it. Every family under spec/scenarios/ starts
# somewhere else and ends the same way, by holding its output against the
# files recorded in `snapshot/`.
#
#   UPDATE_SNAPSHOTS=1 bin/rspec spec/scenarios
#
# rewrites them instead of comparing. The recording runs inside the example,
# so there is no second implementation of the pipeline to keep in step: a
# snapshot holds exactly what the spec ran.
module ScenarioSnapshot
  ROOT = Rails.root.join('spec/scenarios')

  # A scenario is round-tripped when it carries a `snapshot/`. The other
  # directories are input alone: their donor stacks are a corpus that the
  # parser and compatibility specs read, and no stack of ours comes out of
  # them (see spec/scenarios/import/minimal, real_world/user2, user6).
  def self.names(family)
    root = ROOT.join(family)
    Pathname.glob(root.join('**/snapshot'))
            .map { |path| path.parent.relative_path_from(root).to_s }
            .sort
  end

  def self.path(family, name)
    ROOT.join(family, name)
  end

  def self.update?
    ENV['UPDATE_SNAPSHOTS'].present?
  end

  # Call after the export wrote the stack.
  def verify_snapshot!(snapshot_path)
    record_snapshot!(snapshot_path) if ScenarioSnapshot.update?

    # config.yaml is compared parsed, the stack files byte for byte. A
    # recorded config.yaml carries its nested keys sorted (see below), which
    # the exporter has no reason to reproduce.
    aggregate_failures do
      expect_same_config(snapshot_path.join('helios/config.yaml'))
      expect_same_text(Compose.path, snapshot_path.join('compose.yaml'))
      expect_same_text(Env.path, snapshot_path.join('.env'))

      # A snapshot can match and still be unusable: `docker compose` refuses a
      # project whose `depends_on` names a service the export left out.
      expect(dangling_service_dependencies(Compose.path)).to be_empty
    end
  end

  private

  def expect_same_config(recorded)
    expect(load_config(Configuration.path)).to eq(load_config(recorded))
  end

  def expect_same_text(produced, recorded)
    expect(File.read(produced)).to eq(File.read(recorded))
  end

  def record_snapshot!(snapshot_path)
    config_path = snapshot_path.join('helios/config.yaml')
    FileUtils.mkdir_p(config_path.dirname)

    # Keep the root-level key order the exporter chose, but sort the nested
    # keys so a reshuffle inside a section leaves the diff alone.
    sorted = load_config(Configuration.path).transform_values { |value| deep_sort_keys(value) }
    File.write(config_path, Configuration.dump(sorted))

    FileUtils.cp(Compose.path, snapshot_path.join('compose.yaml'))
    FileUtils.cp(Env.path, snapshot_path.join('.env'))
  end

  def load_config(path)
    YAML.safe_load_file(path, permitted_classes: [Date])
  end

  def deep_sort_keys(object)
    case object
    when Hash then object.sort.to_h.transform_values { |value| deep_sort_keys(value) }
    when Array then object.map { |element| deep_sort_keys(element) }
    else object
    end
  end
end

RSpec.configure do |config|
  config.include ScenarioSnapshot, file_path: %r{spec/scenarios/}
end
