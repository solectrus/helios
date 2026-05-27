import TurboStreamPollingController from '@/utils/turboStreamPollingController';

// `polledAtValue` records when refresh last ran, using Date.now() so the
// connect-time staleness check compares a single clock with itself (no
// browser-vs-server skew). The value is mirrored to a data-* attribute
// on the wrapper element, so it survives Stimulus disconnect/reconnect
// across Turbo Drive navigations via data-turbo-permanent. Default 0
// means "never polled" — older than any interval, so the controller
// fires an immediate refresh on the initial page load.
export default class extends TurboStreamPollingController {
  static values = {
    ...TurboStreamPollingController.values,
    polledAt: { type: Number, default: 0 },
  };

  declare polledAtValue: number;

  connect() {
    super.connect();
    if (Date.now() - this.polledAtValue >= this.intervalValue) {
      this.refresh();
    }
  }

  protected async refresh() {
    await super.refresh();
    // Stamp on every attempt, not just successes — a transient failure
    // shouldn't make every subsequent navigation fire a retry; the next
    // 5 s tick will do that.
    this.polledAtValue = Date.now();
  }
}
