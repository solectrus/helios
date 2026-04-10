import { Controller } from '@hotwired/stimulus';
import hljs from 'highlight.js/lib/core';
import yaml from 'highlight.js/lib/languages/yaml';
import properties from 'highlight.js/lib/languages/properties';
import darkThemeUrl from 'highlight.js/styles/a11y-dark.css?url';

hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('properties', properties);

const LINK_ID = 'hljs-theme';

export default class extends Controller {
  static targets = ['code'];

  declare codeTargets: HTMLElement[];

  connect() {
    this.ensureStylesheet();

    this.codeTargets.forEach((code) => {
      hljs.highlightElement(code);
    });
  }

  private ensureStylesheet() {
    if (document.getElementById(LINK_ID)) return;

    const link = document.createElement('link');
    link.id = LINK_ID;
    link.rel = 'stylesheet';
    link.href = darkThemeUrl;
    document.head.appendChild(link);
  }
}
