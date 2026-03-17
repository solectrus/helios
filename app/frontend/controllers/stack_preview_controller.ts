import { Controller } from '@hotwired/stimulus';
import hljs from 'highlight.js/lib/core';
import yaml from 'highlight.js/lib/languages/yaml';
import properties from 'highlight.js/lib/languages/properties';

hljs.registerLanguage('yaml', yaml);
hljs.registerLanguage('properties', properties);

export default class extends Controller {
  static targets = ['code'];

  declare codeTargets: HTMLElement[];

  connect() {
    this.codeTargets.forEach((code) => {
      hljs.highlightElement(code);
    });
  }
}
