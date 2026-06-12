import { Controller } from '@hotwired/stimulus';
import { readLocale } from '../utils/preferences_cookie';

export default class extends Controller {
  static values = {
    datetime: String,
    target: { type: String, default: 'tip' },
  };

  declare datetimeValue: string;
  declare targetValue: string;

  private timeoutId?: number;
  private isConnected = false;
  private boundUpdate = () => this.update();
  private rtf?: Intl.RelativeTimeFormat;
  private rtfLocale?: string;

  connect() {
    this.isConnected = true;
    this.update();
    // Turbo morph preserves this element but resets its textContent to the
    // (empty) server-rendered version, and Stimulus skips `connect`/value
    // callbacks because nothing on the controller changed. Re-run after
    // morph to repaint our text.
    this.element.addEventListener('turbo:morph-element', this.boundUpdate);
  }

  disconnect() {
    this.isConnected = false;
    window.clearTimeout(this.timeoutId);
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

    this.scheduleNextUpdate(Math.abs(diffSec));
  }

  private formatRelative(seconds: number): string {
    const rtf = this.relativeTimeFormat();
    const abs = Math.abs(seconds);

    if (abs < 60) return rtf.format(-seconds, 'second');
    if (abs < 3600) return rtf.format(-Math.round(seconds / 60), 'minute');
    if (abs < 86400) return rtf.format(-Math.round(seconds / 3600), 'hour');
    return rtf.format(-Math.round(seconds / 86400), 'day');
  }

  // Cache the formatter; it ticks every second while showing seconds, so
  // rebuilding it per update is wasted work. Rebuild only when the locale
  // changes (it stays constant across an element's lifetime in practice).
  private relativeTimeFormat(): Intl.RelativeTimeFormat {
    const locale = readLocale();
    if (!this.rtf || this.rtfLocale !== locale) {
      this.rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });
      this.rtfLocale = locale;
    }
    return this.rtf;
  }

  private scheduleNextUpdate(absSeconds: number) {
    window.clearTimeout(this.timeoutId);
    if (!this.isConnected) return;

    const delay = absSeconds < 60 ? 1_000 : 60_000;
    this.timeoutId = window.setTimeout(this.boundUpdate, delay);
  }
}
