import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['startButton', 'stopButton', 'recreateButton'];
  static values = {
    name: String,
  };

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare recreateButtonTarget: HTMLButtonElement;
  declare hasStartButtonTarget: boolean;
  declare hasStopButtonTarget: boolean;
  declare hasRecreateButtonTarget: boolean;
  declare nameValue: string;

  get canStart() {
    return this.hasStartButtonTarget && !this.startButtonTarget.disabled;
  }

  get canStop() {
    return this.hasStopButtonTarget && !this.stopButtonTarget.disabled;
  }

  get canRecreate() {
    return this.hasRecreateButtonTarget && !this.recreateButtonTarget.disabled;
  }

  start() {
    if (!this.hasStartButtonTarget) return Promise.resolve();
    return this.#clickAndWait(this.startButtonTarget);
  }

  stop() {
    if (!this.hasStopButtonTarget) return Promise.resolve();
    return this.#clickAndWait(this.stopButtonTarget);
  }

  recreate() {
    if (!this.hasRecreateButtonTarget) return Promise.resolve();
    return this.#clickAndWait(this.recreateButtonTarget);
  }

  #clickAndWait(button: HTMLButtonElement) {
    return new Promise((resolve) => {
      const form = button.closest('form');
      form?.addEventListener('turbo:submit-end', resolve, { once: true });
      button.click();
    });
  }
}
