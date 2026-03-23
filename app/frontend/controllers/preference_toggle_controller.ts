import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';
import { updatePreferences } from '../utils/preferences_cookie';

export default class extends Controller {
  static targets = ['checkbox', 'container'];
  static values = { key: String };

  declare checkboxTarget: HTMLInputElement;
  declare hasContainerTarget: boolean;
  declare containerTarget: HTMLElement;
  declare keyValue: string;

  toggle() {
    const checked = this.checkboxTarget.checked;
    updatePreferences({ [this.keyValue]: checked });

    if (this.hasContainerTarget) {
      // Instant client-side toggle (e.g. sensor filter)
      this.containerTarget.dataset.showAll = String(checked);
    } else {
      // Full page refresh for toggles that affect server-rendered layout
      Turbo.visit(window.location.href, { action: 'replace' });
    }
  }
}
