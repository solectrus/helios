RSpec.describe ConfigNav::Component, type: :component do
  let(:dir) { config_yaml_dir }

  describe 'the reset block' do
    it 'is hidden while no backup exists' do
      rendered = render_inline(described_class.new)

      expect(rendered).to have_no_text('Reset')
    end

    context 'with a backup of the imported stack' do
      before do
        File.write(File.join(dir, 'compose.yaml'), "services: {}\n")
        File.write(File.join(dir, '.env'), "TZ=Europe/Berlin\n")
        StackBackup.create!
      end

      it 'offers every reset dialog the dialogs component defines' do
        rendered = render_inline(described_class.new)

        buttons = rendered.css('button[data-action="modal-opener#open"]')
        expect(buttons.pluck('data-modal-opener-id-param'))
          .to eq(ResetDialogs::Component::DIALOGS.pluck(:id))
      end

      # `only: :tabs` renders the navigation without the file and reset block.
      it 'is left out when only the tabs are requested' do
        rendered = render_inline(described_class.new(only: :tabs))

        expect(rendered.css('button[data-action="modal-opener#open"]')).to be_empty
      end
    end
  end
end
