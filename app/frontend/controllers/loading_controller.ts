import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['button'];
  static values = {
    text: { type: String, default: 'Loading...' },
    successText: String,
    successDuration: { type: Number, default: 1500 },
    spinner: {
      type: String,
      default: 'loading loading-spinner loading-xs',
    },
  };

  declare buttonTarget: HTMLButtonElement;
  declare textValue: string;
  declare successTextValue: string;
  declare hasSuccessTextValue: boolean;
  declare successDurationValue: number;
  declare spinnerValue: string;

  click(event: Event) {
    const button = event.currentTarget as HTMLButtonElement;

    // Lock current width so the button doesn't reflow when its label changes.
    button.style.minWidth = `${button.getBoundingClientRect().width}px`;

    // Defer disabling to the next tick: setting `disabled` synchronously
    // inside the click handler cancels the pending form submit in some
    // browsers, which swallows downloads triggered by the submit.
    setTimeout(() => {
      this.swapChildren(button, 'span', this.spinnerValue, this.textValue);
      button.disabled = true;

      if (this.hasSuccessTextValue) {
        setTimeout(() => this.showSuccess(button), this.successDurationValue);
      }
    }, 0);
  }

  // Swap the loading spinner for a success checkmark. Used for downloads,
  // which give no completion event — we assume the download has started
  // once `successDurationValue` has elapsed.
  private showSuccess(button: HTMLButtonElement) {
    this.swapChildren(button, 'i', 'fa-solid fa-check', this.successTextValue);
  }

  private swapChildren(
    button: HTMLButtonElement,
    tag: 'span' | 'i',
    className: string,
    text: string,
  ) {
    const indicator = document.createElement(tag);
    indicator.className = className;
    button.replaceChildren(indicator, document.createTextNode(` ${text}`));
  }
}
