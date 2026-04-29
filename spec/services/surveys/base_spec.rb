RSpec.describe Surveys::Base do
  describe '.survey_id' do
    it 'derives the id from the namespace holding the subclass' do
      expect(Surveys::Dashboard::Survey.survey_id).to eq('dashboard')
    end

    it 'underscores camelcased namespaces' do
      expect(Surveys::ReverseProxy::Survey.survey_id).to eq('reverse_proxy')
    end
  end

  describe '#call' do
    let(:fake_survey_class) do
      Class.new(described_class) do
        def self.survey_id
          'fake_survey_for_test'
        end
      end
    end

    let(:json_path) { Rails.root.join('app/services/surveys/fake_survey_for_test/survey.json') }

    around do |example|
      FileUtils.mkdir_p(File.dirname(json_path))
      File.write(json_path, JSON.dump(title: 'Fake'))
      example.run
    ensure
      FileUtils.rm_rf(File.dirname(json_path))
    end

    it 'loads the sidecar JSON next to the subclass' do
      expect(fake_survey_class.new.call).to eq('title' => 'Fake')
    end

    it 'returns nil when the sidecar JSON is missing' do
      File.delete(json_path)

      expect(fake_survey_class.new.call).to be_nil
    end

    it 'returns nil when valid? is false' do
      subclass = Class.new(fake_survey_class) do
        def valid? = false
      end

      expect(subclass.new.call).to be_nil
    end

    it 'passes the parsed JSON to customize! before returning' do
      subclass = Class.new(fake_survey_class) do
        def customize!(data)
          data['extra'] = 'added'
        end
      end

      expect(subclass.new.call).to include('extra' => 'added')
    end
  end
end
