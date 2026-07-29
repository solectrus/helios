RSpec.describe Orchestration::PowerSplitter::Progress do
  include ActiveSupport::Testing::TimeHelpers

  subject(:progress) { described_class.call(container) }

  let(:container) do
    instance_double(
      Orchestration::Container,
      id: 'abc123',
      name: 'solectrus-power-splitter-1',
      running?: true,
    )
  end

  # Docker prefixes every line with an RFC3339 timestamp (`--timestamps`);
  # the power-splitter's own output follows verbatim.
  def stub_log(*lines, at: Time.current)
    log = lines.map { |line| "#{at.utc.iso8601(9)} #{line}\n" }.join
    allow(Open3).to receive(:capture2e).and_return([log, instance_double(Process::Status, success?: true)])
  end

  def day_block(day, at: Time.current)
    ['', "#{at} - Processing day #{day}", '  Pushing 288 records to InfluxDB']
  end

  after { Orchestration::PowerSplitter::State.clear_all }

  before { travel_to Time.zone.parse('2026-07-29 12:00') }

  context 'when historical data is being processed' do
    before do
      stub_log(
        '--- Processing historical data since 2026-07-20',
        *day_block('2026-07-20'),
        *day_block('2026-07-21'),
        *day_block('2026-07-22'),
      )
    end

    # 20th … 22nd of 20th … 29th
    it 'reports the day and the share of days already done' do
      expect(progress).to have_attributes(day: Date.new(2026, 7, 22), percent: 30)
    end
  end

  context 'when the start day has scrolled out of the log window' do
    before { stub_log(*day_block('2026-07-25')) }

    # A recalculation always reprocesses everything since INSTALLATION_DATE,
    # so the configured date is the same start day the log line would name.
    it 'falls back to the configured installation date' do
      with_config_yaml('system' => { 'installation_date' => '2026-07-20' })

      expect(progress).to have_attributes(day: Date.new(2026, 7, 25), percent: 60)
    end

    it 'reports the day without a percentage when no installation date is configured' do
      with_config_yaml

      expect(progress).to have_attributes(day: Date.new(2026, 7, 25), percent: nil)
    end

    it 'reports the day without a percentage when the installation date is in the future' do
      with_config_yaml('system' => { 'installation_date' => '2027-01-01' })

      expect(progress).to have_attributes(day: Date.new(2026, 7, 25), percent: nil)
    end
  end

  context 'when the historical phase has finished' do
    it 'reports no progress' do
      stub_log(
        '--- Processing historical data since 2026-07-20',
        *day_block('2026-07-20'),
        '--- Processing historical data successfully finished',
        'Starting endless loop for processing current data...',
        *day_block('2026-07-29'),
        '  Sleeping for 300 seconds...',
      )

      expect(progress).to be_nil
    end

    # Between two cycles of the endless loop the newest "Processing day" line
    # is briefly the last line — the sleep of the previous cycle keeps it from
    # being mistaken for a running recalculation.
    it 'reports no progress between two cycles of the endless loop' do
      stub_log(
        *day_block('2026-07-29'),
        '  Sleeping for 300 seconds...',
        *day_block('2026-07-29'),
      )

      expect(progress).to be_nil
    end
  end

  context 'when a recalculation has just been triggered' do
    before do
      stub_log(
        *day_block('2026-07-29', at: 1.hour.ago),
        '  Sleeping for 300 seconds...',
        at: 1.hour.ago,
      )
    end

    it 'reports a running recalculation without numbers' do
      Orchestration::PowerSplitter::State.trigger!

      expect(progress).to have_attributes(day: nil, percent: nil)
    end

    it 'reports no progress once the log shows activity after the trigger' do
      Orchestration::PowerSplitter::State.trigger!
      stub_log('  Sleeping for 300 seconds...', at: 1.second.from_now)

      expect(progress).to be_nil
    end

    it 'reports no progress when the trigger is long past' do
      Orchestration::PowerSplitter::State.trigger!
      travel 10.minutes

      expect(progress).to be_nil
    end
  end

  it 'reports no progress for a stopped container' do
    allow(container).to receive(:running?).and_return(false)

    expect(progress).to be_nil
  end

  it 'reports no progress without a container' do
    expect(described_class.call(nil)).to be_nil
  end

  it 'reports no progress when the log cannot be read' do
    allow(Open3).to receive(:capture2e).and_raise(Errno::ENOENT)

    expect(progress).to be_nil
  end

  it 'reads only a bounded tail of the log' do
    stub_log('')

    progress

    expect(Open3).to have_received(:capture2e).with(
      'docker', 'logs', '--tail', '300', '--timestamps', 'solectrus-power-splitter-1'
    )
  end

  # The row re-renders on every /services visit, tab refocus and Docker event,
  # and forking `docker logs` for each of them is the wasteful part.
  describe 'rereading the log' do
    it 'skips it briefly after the log proved nothing is running' do
      stub_log('  Sleeping for 300 seconds...')

      3.times { described_class.call(container) }

      expect(Open3).to have_received(:capture2e).once
    end

    it 'resumes once the idle marker has expired' do
      stub_log('  Sleeping for 300 seconds...')

      described_class.call(container)
      travel 31.seconds
      described_class.call(container)

      expect(Open3).to have_received(:capture2e).twice
    end

    it 'does not skip it for a different container' do
      stub_log('  Sleeping for 300 seconds...')
      other = instance_double(Orchestration::Container, id: 'other', name: 'other', running?: true)

      described_class.call(container)
      described_class.call(other)

      expect(Open3).to have_received(:capture2e).twice
    end

    it 'reads afresh while a recalculation is running' do
      stub_log('--- Processing historical data since 2026-07-20', *day_block('2026-07-22'))

      3.times { described_class.call(container) }

      expect(Open3).to have_received(:capture2e).thrice
    end

    it 'reads afresh right after a recalculation was triggered' do
      stub_log('  Sleeping for 300 seconds...', at: 1.hour.ago)
      described_class.call(container)

      Orchestration::PowerSplitter::State.trigger!

      expect(described_class.call(container)).to have_attributes(day: nil)
    end
  end
end
