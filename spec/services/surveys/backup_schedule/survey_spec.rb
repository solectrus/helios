require 'rails_helper'

RSpec.describe Surveys::BackupSchedule::Survey do
  subject(:survey) { described_class.new.call }

  def schedule_time_element(data)
    data['pages']
      .flat_map { |page| page['elements'] }
      .find { |element| element['name'] == 'schedule_time' }
  end

  it 'returns a parsed survey hash' do
    expect(survey).to be_a(Hash)
    expect(survey['title']).to be_present
  end

  it 'names the configured timezone in the schedule_time hint' do
    allow(Configuration.current).to receive(:system)
      .and_return(double(timezone: 'America/New_York'))

    description = schedule_time_element(survey)['description']

    expect(description['de']).to include('America/New_York')
    expect(description['default']).to include('America/New_York')
  end

  it 'falls back to Europe/Berlin when no timezone is configured' do
    allow(Configuration.current).to receive(:system)
      .and_return(double(timezone: nil))

    description = schedule_time_element(survey)['description']

    expect(description['de']).to include('Europe/Berlin')
    expect(description['default']).to include('Europe/Berlin')
  end
end
