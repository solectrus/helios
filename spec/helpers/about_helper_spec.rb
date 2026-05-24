RSpec.describe AboutHelper do
  describe '#render_markdown' do
    it 'returns empty html for blank input' do
      expect(helper.render_markdown(nil)).to eq('')
      expect(helper.render_markdown('')).to eq('')
    end

    it 'skips H1 (the surrounding section already provides one)' do
      result = helper.render_markdown("# Top heading\n\nPara.")

      expect(result).not_to include('Top heading')
      expect(result).to match(%r{<p class="[^"]*">Para\.</p>})
    end

    it 'demotes ## to a styled H3' do
      result = helper.render_markdown("## Section\n")

      expect(result).to match(%r{<h3 class="[^"]*font-semibold[^"]*">Section</h3>})
    end

    it 'renders paragraphs with inline bold, code and links' do
      result = helper.render_markdown(
        'See **important** `flag` and [docs](https://example.com).',
      )

      expect(result).to include('<strong>important</strong>')
      expect(result).to match(%r{<code class="[^"]*font-mono[^"]*">flag</code>})
      expect(result).to include('href="https://example.com"')
      expect(result).to include('target="_blank"')
    end

    it 'routes *.md links to the components anchor on the same page' do
      result = helper.render_markdown('[Notices](THIRD_PARTY_NOTICES.md)')

      expect(result).to include('href="#components"')
      expect(result).not_to include('THIRD_PARTY_NOTICES.md')
    end

    it 'strips links with non-http(s) schemes, keeping only the escaped label' do
      result = helper.render_markdown('[click](javascript:alert(1))')

      expect(result).not_to include('javascript:')
      expect(result).not_to include('<a ')
      expect(result).to include('click')
    end

    it 'renders unordered lists' do
      result = helper.render_markdown("- one\n- two\n")

      expect(result).to match(/<ul class="[^"]*list-disc[^"]*">/)
      expect(result).to match(%r{<li class="[^"]*">one</li>})
      expect(result).to match(%r{<li class="[^"]*">two</li>})
    end

    it 'escapes HTML in plain text' do
      result = helper.render_markdown('a <script>x</script>')

      expect(result).to include('&lt;script&gt;')
      expect(result).not_to include('<script>')
    end
  end

  describe '#parse_components' do
    let(:markdown) { <<~MD }
      # Header

      ## Ruby Gems

      | Package | License |
      | --- | --- |
      | `rails` | MIT |
      | `pg` | PostgreSQL |

      ## JavaScript Packages

      | Package | License |
      | --- | --- |
      | `turbo` | MIT |
    MD

    it 'flattens all sections into a sorted list with categories' do
      result = helper.parse_components(markdown)

      expect(result.pluck(:name)).to eq(%w[pg rails turbo])
      expect(result.find { |c| c[:name] == 'rails' }).to include(category: 'gem', license: 'MIT')
      expect(result.find { |c| c[:name] == 'turbo' }).to include(category: 'js', license: 'MIT')
    end

    it 'returns an empty array for blank input' do
      expect(helper.parse_components('')).to eq([])
      expect(helper.parse_components(nil)).to eq([])
    end

    it 'ignores the table header row' do
      result = helper.parse_components("## Ruby Gems\n\n| Package | License |\n| --- | --- |\n| `rails` | MIT |\n")

      expect(result.pluck(:name)).to eq(['rails'])
    end
  end
end
