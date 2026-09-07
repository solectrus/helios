RSpec.describe DockerStackHelpers do
  # `clear_data_path!` runs rm_rf on whatever a spec's `data_path` names. A
  # forgotten stub hands it the fallback instead, which in development is
  # `stack/`, the live local stack. The guard is what keeps that from being
  # deleted.
  subject(:helper) { Class.new { include DockerStackHelpers }.new }

  def disposable(path)
    helper.send(:disposable!, path)
  end

  it 'accepts a path below tmp/' do
    expect(disposable(Rails.root.join('tmp/some-itest').to_s)).to eq(
      Rails.root.join('tmp/some-itest').to_s,
    )
  end

  it 'accepts the test-env default, which is disposable by design' do
    expect(disposable(Rails.configuration.data_path)).to be_present
  end

  it 'refuses the live stack directory (the development default)' do
    expect { disposable(Rails.root.join('stack').to_s) }.to raise_error(
      ArgumentError, /only paths below/
    )
  end

  it 'refuses tmp/ itself' do
    expect { disposable(Rails.root.join('tmp').to_s) }.to raise_error(ArgumentError)
  end

  it 'refuses a path that only looks like tmp/' do
    expect { disposable("#{Rails.root.join('tmp')}-evil") }.to raise_error(ArgumentError)
  end

  it 'refuses an escape through ..' do
    expect { disposable(Rails.root.join('tmp/../stack').to_s) }.to raise_error(ArgumentError)
  end

  it 'refuses a blank path' do
    expect { disposable('') }.to raise_error(ArgumentError)
  end
end
