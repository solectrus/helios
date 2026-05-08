import * as Turbo from '@hotwired/turbo';
import PollingController from '../utils/pollingController';

export default class extends PollingController {
  static values = {
    ...PollingController.values,
    url: String,
    enabled: { type: Boolean, default: true },
  };

  declare urlValue: string;
  declare enabledValue: boolean;

  protected shouldPoll(): boolean {
    return this.enabledValue;
  }

  protected async refresh() {
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
