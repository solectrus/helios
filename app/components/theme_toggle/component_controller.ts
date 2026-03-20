import { Controller } from '@hotwired/stimulus';
import { updatePreferences } from '../../frontend/utils/preferences_cookie';

export default class extends Controller {
  static targets = ['sunIcon', 'moonIcon'];

  declare sunIconTarget: HTMLElement;
  declare moonIconTarget: HTMLElement;

  toggle() {
    const html = document.documentElement;
    const currentTheme = html.getAttribute('data-theme');
    const newTheme = currentTheme === 'aqua' ? 'light' : 'aqua';

    html.setAttribute('data-theme', newTheme);
    updatePreferences({ theme: newTheme });
    this.updateIcons();
  }

  private updateIcons() {
    const theme = document.documentElement.getAttribute('data-theme');
    const isDark = theme === 'aqua';

    this.sunIconTarget.classList.toggle('hidden', isDark);
    this.moonIconTarget.classList.toggle('hidden', !isDark);
  }
}
