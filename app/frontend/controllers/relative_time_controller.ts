import { Controller } from '@hotwired/stimulus';
import { readLocale } from '../utils/preferences_cookie';

export default class extends Controller {
  static values = {
    datetime: String,
    target: { type: String, default: 'tip' },
  };

  declare datetimeValue: string;
  declare targetValue: string;

  private intervalId?: number;
  private boundUpdate = () => this.update();

  connect() {
    this.update();
    this.intervalId = window.setInterval(this.boundUpdate, 60_000);
    // Turbo morph preserves this element but resets its textContent to the
    // (empty) server-rendered version, and Stimulus skips `connect`/value
    // callbacks because nothing on the controller changed. Re-run after
    // morph to repaint our text.
    this.element.addEventListener('turbo:morph-element', this.boundUpdate);
  }

  disconnect() {
    window.clearInterval(this.intervalId);
    this.element.removeEventListener('turbo:morph-element', this.boundUpdate);
  }

  datetimeValueChanged() {
    this.update();
  }

  private update() {
    if (!this.datetimeValue) return;

    const timestamp = new Date(this.datetimeValue);
    const now = new Date();
    const diffMs = now.getTime() - timestamp.getTime();
    const diffSec = Math.round(diffMs / 1000);

    const text = this.formatRelative(diffSec);

    if (this.targetValue === 'text') {
      this.element.textContent = text;
    } else {
      (this.element as HTMLElement).dataset.tip = text;
    }
  }

  private formatRelative(seconds: number): string {
    const locale = readLocale();
    const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });
    const abs = Math.abs(seconds);

    if (abs < 60) return rtf.format(-seconds, 'second');
    if (abs < 3600) return rtf.format(-Math.round(seconds / 60), 'minute');
    if (abs < 86400) return rtf.format(-Math.round(seconds / 3600), 'hour');
    return rtf.format(-Math.round(seconds / 86400), 'day');
  }
}
