import { Controller } from '@hotwired/stimulus';

// Polls the server for fresh status when a service is in a transient state
// (pending or health_starting). Uses setInterval to keep polling until the
// status resolves — a single setTimeout would stop after one attempt because
// Stimulus only fires statusValueChanged when the value actually changes.
const POLLING_INTERVAL_MS = 5000;

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

  private pollingInterval?: number;

  disconnect() {
    this.#stopPolling();
  }

  statusValueChanged() {
    if (
      this.statusValue === 'pending' ||
      this.statusValue === 'health_starting'
    ) {
      this.#startPolling();
    } else {
      this.#stopPolling();
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

  #startPolling() {
    if (this.pollingInterval) return;

    this.pollingInterval = window.setInterval(() => {
      this.#reloadFrame();
    }, POLLING_INTERVAL_MS);
  }

  #stopPolling() {
    if (this.pollingInterval) {
      window.clearInterval(this.pollingInterval);
      this.pollingInterval = undefined;
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
