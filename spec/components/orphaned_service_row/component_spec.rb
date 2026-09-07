RSpec.describe OrphanedServiceRow::Component, type: :component do
  subject(:rendered) { render_inline(described_class.new(container:, pending:)) }

  let(:pending) { false }
  let(:state) { 'running' }
  let(:container) { orchestration_container(service: 'dozzle', state:, image: 'amir20/dozzle:latest') }

  it 'marks a running orphan green' do
    expect(rendered.css('.bg-success')).to be_present
  end

  context 'with a stopped orphan' do
    let(:state) { 'exited' }

    it 'marks it neutral' do
      expect(rendered.css('.bg-neutral')).to be_present
    end
  end

  context 'when an operation is in flight' do
    let(:pending) { true }

    it 'shows a spinner instead of the status dot' do
      expect(rendered.css('.loading-spinner')).to be_present
      expect(rendered.css('.bg-success')).to be_empty
    end
  end
end
