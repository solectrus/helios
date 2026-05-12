import PollingController from '@/utils/pollingController';

// Polls the server for fresh status while a service is in a transient state
// (pending or health_starting) by re-fetching the Turbo Frame's `data-src`.
// `shouldPoll()` is re-evaluated whenever `statusValue` changes, so the timer
// stops automatically as soon as the status resolves.
export default class extends PollingController {
  static targets = ['startButton', 'stopButton', 'recreateButton'];
  static values = {
    ...PollingController.values,
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

  statusValueChanged() {
    this.evaluatePolling();
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

  protected shouldPoll(): boolean {
    return (
      this.statusValue === 'pending' || this.statusValue === 'health_starting'
    );
  }

  protected refresh() {
    const frame = this.element as HTMLElement;
    const src = frame.dataset.src;
    if (!src) return;

    frame.removeAttribute('complete');
    frame.removeAttribute('src');
    frame.setAttribute('src', src);
  }

  #clickAndWait(button: HTMLButtonElement) {
    return new Promise((resolve) => {
      const form = button.closest('form');
      form?.addEventListener('turbo:submit-end', resolve, { once: true });
      button.click();
    });
  }
}
