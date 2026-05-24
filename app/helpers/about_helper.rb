require 'commonmarker'

module AboutHelper
  PROSE_CLASSES = {
    'h3' => 'text-base-content mt-8 mb-3 text-base font-semibold tracking-tight first:mt-0',
    'p' => 'text-base-content/80 mb-4 leading-relaxed',
    'ul' => 'text-base-content/80 mb-4 list-disc space-y-1.5 pl-5',
    'li' => 'leading-relaxed',
    'code' => 'bg-base-content/10 rounded px-1.5 py-0.5 font-mono text-[0.85em]',
  }.freeze
  private_constant :PROSE_CLASSES

  SAFE_LINK_SCHEMES = %w[http:// https:// #].freeze
  private_constant :SAFE_LINK_SCHEMES

  def render_markdown(markdown)
    return ''.html_safe if markdown.blank?

    html = Commonmarker.to_html(
      markdown.to_s,
      options: { render: { escape: true, unsafe: false } },
    )
    transform_html(html).html_safe # rubocop:disable Rails/OutputSafety
  end

  def parse_components(markdown)
    parse_tables(markdown)
      .flat_map { |section| flatten_section(section) }
      .sort_by { |row| row[:name].downcase }
  end

  private

  COMPONENT_CATEGORIES = {
    'Ruby Gems' => 'gem',
    'JavaScript Packages' => 'js',
  }.freeze
  private_constant :COMPONENT_CATEGORIES

  def transform_html(html)
    fragment = Nokogiri::HTML5.fragment(html)
    # Drop the first H1 entirely — the surrounding section already has one.
    fragment.at_css('h1')&.remove
    # Commonmarker injects anchor links inside every heading. Strip them
    # before adding our own classes, otherwise they'd be styled as user links.
    fragment.css('a.anchor').each(&:remove)
    # Demote ## headings one level since the page already has h1 + h2.
    fragment.css('h2').each { |node| node.name = 'h3' }

    PROSE_CLASSES.each do |tag, css_class|
      fragment.css(tag).each { |node| node['class'] = css_class }
    end
    fragment.css('a').each { |node| transform_link(node) }

    fragment.to_html
  end

  def transform_link(node)
    href = node['href'].to_s

    if href.end_with?('.md')
      # Same-repo *.md references would 404 — point at the components list.
      node['href'] = '#components'
    elsif SAFE_LINK_SCHEMES.none? { |scheme| href.start_with?(scheme) }
      node.replace(Nokogiri::XML::Text.new(node.content, node.document))
      return
    end

    node['class'] = 'link link-primary'
    return if node['href'].start_with?('#')

    node['target'] = '_blank'
    node['rel'] = 'noopener noreferrer'
  end

  def flatten_section(section)
    category = COMPONENT_CATEGORIES[section[:heading]]
    section[:rows].map do |name, license|
      { category: category, name: name.to_s.delete('`'), license: license }
    end
  end

  def parse_tables(markdown)
    return [] if markdown.blank?

    sections = []
    current = nil
    markdown.each_line do |raw|
      line = raw.chomp
      if line.start_with?('## ')
        current = { heading: line[3..], rows: [] }
        sections << current
      elsif current && table_row?(line)
        cells = parse_row(line)
        current[:rows] << cells if cells
      end
    end
    sections
  end

  def table_row?(line)
    line.start_with?('|') && !table_separator_row?(line)
  end

  def table_separator_row?(line)
    line.match?(/\|[\s\-:|]+\|/)
  end

  def parse_row(line)
    cells = line.split('|').map(&:strip).reject(&:empty?)
    return nil if cells.size != 2 || cells.first == 'Package'

    cells
  end
end
