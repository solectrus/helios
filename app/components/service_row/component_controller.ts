import PollingController from '@/utils/pollingController';

// Polls the server for fresh status while a service is in a transient state
// (pending, health_starting or recalculating) by re-fetching the enclosing
// Turbo Frame's `data-src`. The controller is mounted on an element inside
// that frame: a frame reload swaps its children, so each response brings a
// fresh instance whose values reflect what the server just reported, and the
// timer stops as soon as the state resolves.
export default class extends PollingController {
  static targets = ['startButton', 'stopButton', 'recreateButton'];
  static values = {
    ...PollingController.values,
    name: String,
    status: String,
    recalculating: Boolean,
  };

  declare startButtonTarget: HTMLButtonElement;
  declare stopButtonTarget: HTMLButtonElement;
  declare recreateButtonTarget: HTMLButtonElement;
  declare hasStartButtonTarget: boolean;
  declare hasStopButtonTarget: boolean;
  declare hasRecreateButtonTarget: boolean;
  declare nameValue: string;
  declare statusValue: string;
  declare recalculatingValue: boolean;

  statusValueChanged() {
    this.evaluatePolling();
  }

  recalculatingValueChanged() {
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

  protected shouldPoll(): boolean {
    return (
      this.statusValue === 'pending' ||
      this.statusValue === 'health_starting' ||
      // Power splitter recalculating: keeps the progress badge counting up.
      this.recalculatingValue
    );
  }

  protected refresh() {
    // The controller sits inside the frame so that every reload re-reads its
    // values; the element to reload is therefore the enclosing frame.
    const frame = this.element.closest('turbo-frame') as HTMLElement | null;
    const src = frame?.dataset.src;
    if (!frame || !src) return;

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
