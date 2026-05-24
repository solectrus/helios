RSpec.describe About::ComponentText do
  describe '.for' do
    context 'with a gem category' do
      it 'returns metadata + license text for a known gem' do
        payload = described_class.for(category: 'gem', name: 'rake')

        expect(payload).to include(:heading, :subtitle, :text, :url)
        expect(payload[:heading]).to eq('rake')
        expect(payload[:subtitle]).to match(/\d+\.\d+/) # version
        expect(payload[:text]).to be_a(String).and(be_present)
      end

      it 'returns nil for an unknown gem' do
        expect(described_class.for(category: 'gem', name: 'no-such-gem')).to be_nil
      end
    end

    context 'with a js category' do
      subject(:payload) { described_class.for(category: 'js', name: '@hotwired/stimulus') }

      it 'parses metadata from the matching THIRD_PARTY_NOTICES.md section' do
        expect(payload).to include(
          heading: '@hotwired/stimulus',
          subtitle: match(/\A\d+\.\d+.* · MIT\z/),
          url: 'https://stimulus.hotwired.dev',
        )
      end

      it 'returns the license body without the metadata block' do
        expect(payload[:text]).to include('MIT License').and(satisfy { |t| t.exclude?('- Version:') })
      end

      it 'returns nil for a section that is not present' do
        expect(described_class.for(category: 'js', name: 'no-such-package')).to be_nil
      end
    end

    it 'returns nil for an unknown category' do
      expect(described_class.for(category: 'mystery', name: 'rake')).to be_nil
    end
  end
end
