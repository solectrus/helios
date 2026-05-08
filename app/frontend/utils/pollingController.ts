import { Controller } from '@hotwired/stimulus';

// Base class for Stimulus controllers that periodically refresh content.
// Subclasses implement `refresh()` and may override `shouldPoll()` to skip
// activation. Polling pauses while the tab is hidden and resumes on focus,
// and the timer/listener are torn down when the controller disconnects.
export default abstract class PollingController extends Controller {
  static values = {
    interval: { type: Number, default: 5000 },
  };

  declare intervalValue: number;

  private timer: ReturnType<typeof setInterval> | null = null;
  private boundVisibilityHandler: (() => void) | null = null;

  connect() {
    if (!this.shouldPoll()) return;

    this.boundVisibilityHandler = this.handleVisibilityChange.bind(this);
    document.addEventListener('visibilitychange', this.boundVisibilityHandler);
    this.startPolling();
  }

  disconnect() {
    this.stopPolling();
    if (this.boundVisibilityHandler) {
      document.removeEventListener(
        'visibilitychange',
        this.boundVisibilityHandler,
      );
      this.boundVisibilityHandler = null;
    }
  }

  protected shouldPoll(): boolean {
    return true;
  }

  protected abstract refresh(): void | Promise<void>;

  private startPolling() {
    this.stopPolling();
    this.timer = setInterval(() => this.refresh(), this.intervalValue);
  }

  private stopPolling() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private handleVisibilityChange() {
    if (document.hidden) {
      this.stopPolling();
    } else {
      this.refresh();
      this.startPolling();
    }
  }
}
