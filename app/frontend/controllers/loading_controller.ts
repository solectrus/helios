import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['button'];
  static values = {
    text: { type: String, default: 'Loading...' },
  };

  declare buttonTarget: HTMLButtonElement;
  declare textValue: string;

  click(event: Event) {
    const button = event.currentTarget as HTMLButtonElement;
    button.classList.add('loading', 'loading-spinner');
    button.disabled = true;

    // Store original text and replace with loading text
    if (!button.dataset.originalText) {
      button.dataset.originalText = button.textContent ?? '';
      button.textContent = this.textValue;
    }
  }
}
