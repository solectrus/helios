import TurboStreamPollingController from '../utils/turboStreamPollingController';

const isTurboPreview = () =>
  document.documentElement.hasAttribute('data-turbo-preview');

export default class extends TurboStreamPollingController {
  static values = {
    ...TurboStreamPollingController.values,
    enabled: { type: Boolean, default: true },
  };

  declare enabledValue: boolean;

  connect() {
    super.connect();
    // The page renders without readings, so fetch the first batch right away
    // instead of waiting a full interval — otherwise the value cells would
    // stay blank for up to `interval` ms.
    if (this.shouldPoll()) this.refresh();
  }

  // Never poll while Turbo shows a cached preview: controllers connect in the
  // preview DOM too, and that DOM is replaced by the real response a few
  // frames later, which connects this controller a second time. Without the
  // guard every revisit costs two rounds of InfluxDB queries, one of them for
  // a DOM nobody ever sees — and a preview outliving the interval would keep
  // querying.
  protected shouldPoll(): boolean {
    return this.enabledValue && !isTurboPreview();
  }
}
