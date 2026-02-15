import { Controller } from '@hotwired/stimulus';

export default class extends Controller {
  static targets = ['startButton', 'stopButton', 'recreateButton'];
  static values = {
    name: String,
    status: String,
  };

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare recreateButtonTarget: HTMLButtonElement;
  declare hasStartButtonTarget: boolean;
  declare hasStopButtonTarget: boolean;
  declare hasRecreateButtonTarget: boolean;
  declare nameValue: string;
  declare statusValue: string;

  private pendingTimeout?: number;

  disconnect() {
    this.#clearPendingTimeout();
  }

  statusValueChanged() {
    // If status changes to pending or health_starting, start a timeout to reload the frame.
    // This handles the edge case where ActionCable broadcast is missed.
    if (
      this.statusValue === 'pending' ||
      this.statusValue === 'health_starting'
    ) {
      this.#startPendingTimeout();
    } else {
      this.#clearPendingTimeout();
    }
  }

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

  open(event: Event) {
    event.preventDefault();
    const target = event.currentTarget as HTMLElement;
    const port = target.dataset.port;
    if (port) {
      window.open(`http://${window.location.hostname}:${port}`, '_blank');
    }
  }

  #clickAndWait(button: HTMLButtonElement) {
    return new Promise((resolve) => {
      const form = button.closest('form');
      form?.addEventListener('turbo:submit-end', resolve, { once: true });
      button.click();
    });
  }

  #startPendingTimeout() {
    this.#clearPendingTimeout();

    // After 3 seconds, reload the frame if still pending
    // This ensures we catch the real state even if the ActionCable broadcast was missed
    this.pendingTimeout = window.setTimeout(() => {
      this.#reloadFrame();
    }, 3000);
  }

  #clearPendingTimeout() {
    if (this.pendingTimeout) {
      window.clearTimeout(this.pendingTimeout);
      this.pendingTimeout = undefined;
    }
  }

  #reloadFrame() {
    const frame = this.element as HTMLElement;
    const src = frame.dataset.src;
    if (!src) return;

    frame.removeAttribute('complete');
    frame.removeAttribute('src');
    frame.setAttribute('src', src);
  }
}
