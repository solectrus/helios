import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';
import { updatePreferences } from '../utils/preferences_cookie';

export default class extends Controller {
  static targets = ['checkbox'];
  static values = { key: String };

  declare checkboxTarget: HTMLInputElement;
  declare keyValue: string;

  toggle() {
    updatePreferences({ [this.keyValue]: this.checkboxTarget.checked });
    Turbo.visit(window.location.href, { action: 'replace' });
  }
}
