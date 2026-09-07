RSpec.describe ResetDialogs::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new) }

  let(:dir) { config_yaml_dir }
  let(:compose_yaml) { "services:\n  postgresql:\n    image: postgres:18-alpine\n" }

  before do
    File.write(File.join(dir, 'compose.yaml'), compose_yaml)
    File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
    StackBackup.create!
  end

  it 'offers one dialog per reset action' do
    expect(rendered).to have_text('Reset configuration')
    expect(rendered).to have_text('Delete backups')
  end

  it 'names the compose file the reset would restore' do
    expect(rendered).to have_text(Compose.filename)
  end

  it 'stays hidden without a backup' do
    StackBackup.discard!

    expect(described_class.new.render?).to be(false)
  end

  # Restoring an older PostgreSQL major cannot start against the already
  # migrated data directory, so only the reset is blocked.
  context 'when the backup pins an older PostgreSQL major' do
    let(:compose_yaml) { "services:\n  postgresql:\n    image: postgres:17-alpine\n" }

    before { Configuration.current.update('postgresql', { 'image' => 'postgres:18-alpine' }) }

    it 'disables the reset but keeps discarding available' do
      expect(rendered.css('button[type="submit"][disabled]').size).to eq(1)
    end
  end
end
