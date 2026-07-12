import { Controller } from '@hotwired/stimulus';

const LINK_ID = 'hljs-theme';

export default class extends Controller {
  static targets = ['code'];

  declare codeTargets: HTMLElement[];

  async connect() {
    // highlight.js core + languages + its theme CSS load only when a stack
    // preview is actually rendered (the /services/files/show page), not on
    // every page via the eager controller glob. Dynamic imports split them
    // into an async chunk. The theme URL is pulled in here too — a top-level
    // import would tie the whole highlight chunk back into the eager graph.
    const [{ default: hljs }, { default: yaml }, { default: properties }, css] =
      await Promise.all([
        import('highlight.js/lib/core'),
        import('highlight.js/lib/languages/yaml'),
        import('highlight.js/lib/languages/properties'),
        import('highlight.js/styles/a11y-dark.css?url'),
      ]);
    if (!this.element.isConnected) return;

    this.ensureStylesheet(css.default);

    // Idempotent across reconnects — registering an already-known language
    // just overwrites the same definition.
    hljs.registerLanguage('yaml', yaml);
    hljs.registerLanguage('properties', properties);

    this.codeTargets.forEach((code) => {
      hljs.highlightElement(code);
    });
  }

  private ensureStylesheet(href: string) {
    if (document.getElementById(LINK_ID)) return;

    const link = document.createElement('link');
    link.id = LINK_ID;
    link.rel = 'stylesheet';
    link.href = href;
    document.head.appendChild(link);
  }
}
