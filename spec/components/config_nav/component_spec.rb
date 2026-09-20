RSpec.describe ConfigNav::Component, type: :component do
  let(:dir) { config_yaml_dir }

  describe 'the warning sign' do
    before { with_config_yaml }

    def signs(rendered)
      rendered
        .css('a')
        .select { |a| a.css('i.fa-triangle-exclamation').any? }
        .to_h { |a| [a['href'], a.css('i.fa-triangle-exclamation').attr('class').value] }
    end

    # The commissioning date is missing, so the Settings entry is the one that
    # leads on, and the only one in the warning color.
    it 'marks the entry that carries an open setting' do
      rendered = render_inline(described_class.new(active_tab: :sensors))

      expect(signs(rendered).transform_values { |css| css.include?('text-warning') })
        .to eq({ '/settings' => true })
    end

    it 'holds the sign back on the entry that is already open' do
      rendered = render_inline(described_class.new(active_tab: :settings))

      expect(signs(rendered)['/settings']).to include(Header::Component::MUTED_WARNING_CLASSES)
    end

    # The sign is an icon, and its tooltip lives in an attribute a screen
    # reader does not read. So the entry carries the words as well (the top
    # navigation and the dock do the same).
    it 'names what it marks, for a screen reader' do
      rendered = render_inline(described_class.new(active_tab: :sensors))

      expect(rendered.css('a .sr-only').text).to include(I18n.t('configurations.show.incomplete'))
    end
  end

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
