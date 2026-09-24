RSpec.describe BuildInfo do
  subject(:build_info) { described_class.read(path.to_s) }

  let(:dir) { Pathname.new(Dir.mktmpdir) }
  let(:path) { dir.join('build-info') }

  after { dir.rmtree }

  context 'without the file, as in a working copy' do
    it { is_expected.to eq({}) }
  end

  # The file names the build of the image, so a value an older image left in
  # the environment of the container cannot change the version.
  context 'with the file the base image writes' do
    before do
      path.write("COMMIT_TIME=2026-09-24T12:00:00+02:00\nCOMMIT_VERSION=v0.5.0-3-g1a2b3c4\nCOMMIT_BRANCH=\n")
    end

    it 'holds the Git metadata of the build' do
      expect(build_info).to eq(
        'COMMIT_TIME' => '2026-09-24T12:00:00+02:00',
        'COMMIT_VERSION' => 'v0.5.0-3-g1a2b3c4',
        'COMMIT_BRANCH' => '',
      )
    end
  end
end
