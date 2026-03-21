import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';

export default class extends Controller {
  static values = {
    interval: { type: Number, default: 5000 },
    url: String,
    enabled: { type: Boolean, default: true },
  };

  declare intervalValue: number;
  declare urlValue: string;
  declare enabledValue: boolean;

  private timer: ReturnType<typeof setInterval> | null = null;
  private boundVisibilityHandler!: () => void;

  connect() {
    if (!this.enabledValue) return;

    this.boundVisibilityHandler = this.handleVisibilityChange.bind(this);
    document.addEventListener('visibilitychange', this.boundVisibilityHandler);
    this.startPolling();
  }

  disconnect() {
    this.stopPolling();
    document.removeEventListener(
      'visibilitychange',
      this.boundVisibilityHandler,
    );
  }

  private startPolling() {
    this.stopPolling();
    this.timer = setInterval(() => this.reload(), this.intervalValue);
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
      this.reload();
      this.startPolling();
    }
  }

  private async reload() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: 'text/vnd.turbo-stream.html' },
      });

      if (response.ok) {
        const html = await response.text();
        Turbo.renderStreamMessage(html);
      }
    } catch {
      // Silently ignore network errors during polling
    }
  }
}
