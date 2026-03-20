import { Controller } from '@hotwired/stimulus';
import hljs from 'highlight.js/lib/core';
import yaml from 'highlight.js/lib/languages/yaml';
import properties from 'highlight.js/lib/languages/properties';
import lightThemeUrl from 'highlight.js/styles/a11y-light.css?url';
import darkThemeUrl from 'highlight.js/styles/a11y-dark.css?url';
import { isDarkMode, onThemeChange } from '../utils/theme';

hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('properties', properties);

const LINK_ID = 'hljs-theme';

export default class extends Controller {
  static targets = ['code'];

  declare codeTargets: HTMLElement[];
  private unsubscribeTheme: (() => void) | null = null;

  connect() {
    this.applyTheme();
    this.unsubscribeTheme = onThemeChange(() => this.applyTheme());

    this.codeTargets.forEach((code) => {
      hljs.highlightElement(code);
    });
  }

  disconnect() {
    this.unsubscribeTheme?.();
  }

  private applyTheme() {
    const href = isDarkMode() ? darkThemeUrl : lightThemeUrl;

    let link = document.getElementById(LINK_ID) as HTMLLinkElement | null;
    if (!link) {
      link = document.createElement('link');
      link.id = LINK_ID;
      link.rel = 'stylesheet';
      document.head.appendChild(link);
    }

    if (link.getAttribute('href') !== href) {
      link.href = href;
    }
  }
}
