import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 5000 },
    url: String,
  };

  declare delayValue: number;
  declare urlValue: string;

  private timer: ReturnType<typeof setTimeout> | null = null;

  connect() {
    this.timer = setTimeout(() => {
      Turbo.visit(this.urlValue || window.location.pathname, {
        action: 'replace',
      });
    }, this.delayValue);
  }

  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }
}
