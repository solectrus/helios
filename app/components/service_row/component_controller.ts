import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['startButton', 'stopButton', 'restartButton'];
  static values = {
    name: String,
  };

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare restartButtonTarget: HTMLButtonElement;
  declare nameValue: string;

  get canStart() {
    return !this.startButtonTarget.disabled;
  }

  get canStop() {
    return !this.stopButtonTarget.disabled;
  }

  start() {
    return this.#clickAndWait(this.startButtonTarget);
  }

  stop() {
    return this.#clickAndWait(this.stopButtonTarget);
  }

  restart() {
    return this.#clickAndWait(this.restartButtonTarget);
  }

  #clickAndWait(button: HTMLButtonElement) {
    return new Promise((resolve) => {
      const form = button.closest('form');
      form?.addEventListener('turbo:submit-end', resolve, { once: true });
      button.click();
    });
  }
}
