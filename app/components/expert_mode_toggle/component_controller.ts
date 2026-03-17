import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';

const COOKIE_NAME = 'expert_mode';

export default class extends Controller {
  static targets = ['checkbox'];

  declare checkboxTarget: HTMLInputElement;

  connect() {
    this.checkboxTarget.checked = this.isEnabled();
  }

  toggle() {
    const enabled = this.checkboxTarget.checked;
    const maxAge = 60 * 60 * 24 * 365; // 1 year
    document.cookie = `${COOKIE_NAME}=${enabled}; path=/; SameSite=Lax; max-age=${maxAge}`;

    Turbo.visit(window.location.href, { action: 'replace' });
  }

  private isEnabled(): boolean {
    return document.cookie.split('; ').some((c) => c === `${COOKIE_NAME}=true`);
  }
}
