import TurboStreamPollingController from '../utils/turboStreamPollingController';

export default class extends TurboStreamPollingController {
  static values = {
    ...TurboStreamPollingController.values,
    enabled: { type: Boolean, default: true },
  };

  declare enabledValue: boolean;

  connect() {
    super.connect();
    // The content frame now renders without readings, so fetch the first batch
    // right away instead of waiting a full interval — otherwise the value cells
    // would stay blank for up to `interval` ms.
    if (this.shouldPoll()) this.refresh();
  }

  protected shouldPoll(): boolean {
    return this.enabledValue;
  }
}
