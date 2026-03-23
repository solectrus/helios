import { Controller } from '@hotwired/stimulus';
import { readLocale } from '../utils/preferences_cookie';

export default class extends Controller {
  static values = {
    datetime: String,
  };

  declare datetimeValue: string;

  connect() {
    this.update();
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

    const el = this.element as HTMLElement;
    el.dataset.tip = this.formatRelative(diffSec);
    el.classList.add('tooltip', 'tooltip-left', 'before:text-xs');
  }

  private formatRelative(seconds: number): string {
    const locale = readLocale();
    const rtf = new Intl.RelativeTimeFormat(locale, { numeric: 'auto' });

    if (seconds < 60) return rtf.format(-seconds, 'second');
    if (seconds < 3600) return rtf.format(-Math.round(seconds / 60), 'minute');
    if (seconds < 86400) return rtf.format(-Math.round(seconds / 3600), 'hour');
    return rtf.format(-Math.round(seconds / 86400), 'day');
  }
}
