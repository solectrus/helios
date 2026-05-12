import * as Turbo from '@hotwired/turbo';
import PollingController from './pollingController';

export default abstract class TurboStreamPollingController extends PollingController {
  static values = {
    ...PollingController.values,
    url: String,
  };

  declare urlValue: string;

  protected async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: 'text/vnd.turbo-stream.html' },
      });

      if (response.ok) {
        Turbo.renderStreamMessage(await response.text());
      }
    } catch {
      // Transient network errors are expected — retry on the next tick.
    }
  }
}
