import TurboStreamPollingController from '../utils/turboStreamPollingController';

export default class extends TurboStreamPollingController {
  static values = {
    ...TurboStreamPollingController.values,
    enabled: { type: Boolean, default: true },
  };

  declare enabledValue: boolean;

  protected shouldPoll(): boolean {
    return this.enabledValue;
  }
}
