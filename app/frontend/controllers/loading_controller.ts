import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['button'];
  static values = {
    text: { type: String, default: 'Loading...' },
    successText: String,
    successDuration: { type: Number, default: 1500 },
  };

  declare buttonTarget: HTMLButtonElement;
  declare textValue: string;
  declare successTextValue: string;
  declare hasSuccessTextValue: boolean;
  declare successDurationValue: number;

  click(event: Event) {
    const button = event.currentTarget as HTMLButtonElement;

    // Defer disabling to the next tick: setting `disabled` synchronously
    // inside the click handler cancels the pending form submit in some
    // browsers, which swallows downloads triggered by the submit.
    setTimeout(() => {
      button.classList.add('loading', 'loading-spinner');
      button.disabled = true;
      button.textContent = this.textValue;

      if (this.hasSuccessTextValue) {
        setTimeout(() => this.showSuccess(button), this.successDurationValue);
      }
    }, 0);
  }

  // Swap the loading spinner for a success checkmark. Used for downloads,
  // which give no completion event — we assume the download has started
  // once `successDurationValue` has elapsed.
  private showSuccess(button: HTMLButtonElement) {
    button.classList.remove('loading', 'loading-spinner');

    const icon = document.createElement('i');
    icon.className = 'fa-solid fa-check';
    button.replaceChildren(icon, document.createTextNode(' '));
    button.append(this.successTextValue);
  }
}
