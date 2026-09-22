import { Controller } from '@hotwired/stimulus';
import type { Model } from 'survey-core';
import { loadSurveyRuntime } from '../utils/survey_loader';
import { readLocale } from '../utils/preferences_cookie';
import { prefersReducedMotion } from '../utils/prefers_reduced_motion';
import { loadingSpinner } from '../utils/loading_spinner';
import { SurveyDropdowns } from '../utils/survey_dropdowns';
import { wirePasswordReveal } from '../utils/survey_password_reveal';
import {
  wireBrowserHostOffer,
  type BrowserHostOffer,
} from '../utils/survey_browser_host';

// Connection-test labels shown before the server replies (the result message
// itself comes back localized from the server). Kept here because they belong
// to a transient UI state SurveyJS never sees.
const TEST_LABELS = {
  de: { pending: 'Verbindung wird geprüft…', failed: 'Prüfung fehlgeschlagen' },
  default: { pending: 'Testing connection…', failed: 'Check failed' },
};

// What a probe answered. 'warn' is an answer the probe could not settle: the
// configuration may still be right, so it reads as a note, not as a failure.
type ConnectionStatusState = 'pending' | 'ok' | 'warn' | 'error';

const CONNECTION_STATUS_ICONS: Record<ConnectionStatusState, string> = {
  pending: 'fa-spinner fa-spin',
  ok: 'fa-circle-check',
  warn: 'fa-triangle-exclamation',
  error: 'fa-circle-xmark',
};

// Survey.JS styles are imported in application.css for correct cascade order

export default class extends Controller<HTMLElement> {
  static targets = ['container', 'output'];
  static values = {
    url: String,
    formId: String,
    fieldName: { type: String, default: 'survey_data' },
    initialData: { type: Object, default: {} },
    connectionTestUrl: { type: String, default: '' },
  };

  declare containerTarget: HTMLElement;
  declare outputTarget: HTMLElement;
  declare hasOutputTarget: boolean;
  declare urlValue: string;
  declare formIdValue: string;
  declare hasFormIdValue: boolean;
  declare fieldNameValue: string;
  declare initialDataValue: Record<string, unknown>;
  declare connectionTestUrlValue: string;

  private survey: Model | null = null;
  private applyingPageChange = false;
  private lastProgress = -1;
  private readonly resetTestsOnInput = () => this.resetConnectionTests();
  private dropdowns: SurveyDropdowns | null = null;

  async connect() {
    await this.initSurvey();
  }

  disconnect() {
    this.containerTarget.removeEventListener('input', this.resetTestsOnInput);
    this.dropdowns?.release();
    this.dropdowns = null;
    this.survey?.dispose();
    this.survey = null;
  }

  private updateProgress() {
    if (!this.survey) return;
    const total = this.survey.visiblePageCount;
    const ratio = total > 1 ? (this.survey.currentPageNo + 1) / total : 1;
    const percent = Math.round(ratio * 100);
    if (percent === this.lastProgress) return;
    this.lastProgress = percent;
    this.element.style.setProperty('--survey-progress', `${percent}%`);
  }

  // View transitions drive the modal-resize and page-change animations;
  // skipped without browser support or when reduced motion is preferred.
  private get viewTransitionsEnabled() {
    return (
      typeof document.startViewTransition === 'function' &&
      !prefersReducedMotion()
    );
  }

  // Spinner shown in the container while the survey JSON is fetched, so the
  // modal never sits visually empty between frame-load and survey render.
  private showLoading() {
    this.containerTarget.replaceChildren(loadingSpinner());
  }

  // Replace the spinner with the rendered survey.
  private renderSurvey() {
    if (!this.survey) return;
    this.containerTarget.replaceChildren();
    this.survey.render(this.containerTarget);
  }

  // Render the survey inside a view transition so the modal box animates to
  // its final size (it carries the dialog-modal-box view-transition-name).
  // The form is hidden during the resize and faded in once the box has
  // settled, so the frame grows first and the content appears second.
  private async renderSurveyAnimated() {
    const transition = startSurveyTransition(() => {
      this.containerTarget.style.opacity = '0';
      this.renderSurvey();
    });

    await transition.finished;

    this.containerTarget.style.removeProperty('opacity');
    this.containerTarget.animate([{ opacity: 0 }, { opacity: 1 }], {
      duration: 120,
      easing: 'ease-out',
    });
  }

  private async initSurvey() {
    this.showLoading();

    // Fetch the survey JSON while the SurveyJS runtime chunk downloads in
    // parallel — the spinner covers both.
    const [{ Model, theme }, surveyJson] = await Promise.all([
      loadSurveyRuntime(),
      fetch(this.urlValue).then((response) => response.json()),
    ]);
    if (!this.element.isConnected) return;

    // Read and remove before the model is built, so the marker never reaches
    // SurveyJS as a property it does not know.
    const browserHostOffer = surveyJson.offerBrowserHost as
      BrowserHostOffer | undefined;
    delete surveyJson.offerBrowserHost;

    this.survey = new Model(surveyJson);
    this.survey.applyTheme(theme);

    // Built-in progress bar is replaced by a CSS underline driven by
    // --survey-progress (see updateProgress).
    this.survey.locale = readLocale();
    this.survey.showProgressBar = 'off';
    this.suppressNavTooltips();
    this.updateProgress();
    this.survey.onCurrentPageChanged.add(() => this.updateProgress());
    this.survey.onPageVisibleChanged.add(() => this.updateProgress());

    // Animate height changes between pages instead of snapping.
    this.survey.onCurrentPageChanging.add((sender, options) => {
      // The assignment below turns the page for real and fires this event a
      // second time. Let that one through, it is already inside a transition.
      if (this.applyingPageChange || !this.viewTransitionsEnabled) return;

      options.allowChanging = false;

      // A page turn that arrives while the previous one still animates gets
      // its own transition. The browser drops the running one, which snaps the
      // modal to the page that transition was heading for, and the new one
      // starts from there. Turning the page outside a transition instead would
      // leave the old snapshot on screen, and the modal would flicker once the
      // browser drops that snapshot.
      startSurveyTransition(() => {
        this.applyingPageChange = true;
        try {
          sender.currentPage = options.newCurrentPage;
        } finally {
          this.applyingPageChange = false;
        }
      });
    });

    // Render text with a trailing hint: "Main text\n\nHint text" becomes
    // a headline followed by a smaller muted subtitle. Used for radio choices.
    // HTML is allowed in both parts because survey JSON is fully under our control.
    this.survey.onTextMarkdown.add((_sender, options) => {
      const separator = options.text.indexOf('\n\n');
      if (separator === -1) return;

      const main = options.text.slice(0, separator);
      const hint = options.text.slice(separator + 2);
      options.html = `${main}<span class="sd-hint">${hint}</span>`;
    });

    // Load initial data if provided
    if (Object.keys(this.initialDataValue).length > 0) {
      this.survey.mergeData(this.initialDataValue);
    }

    if (browserHostOffer) {
      wireBrowserHostOffer(
        this.survey,
        browserHostOffer,
        window.location.hostname,
      );
    }

    // Handle survey completing (fires before DOM changes)
    this.survey.onCompleting.add((sender, options) => {
      // Prevent SurveyJS completion. This avoids UI changes.
      options.allow = false;

      // Submit form and close modal
      this.submitForm(sender.data);
      this.dispatch('formSubmitted');
    });

    // Handle survey completion (only for non-form mode)
    this.survey.onComplete.add((sender) => {
      this.handleComplete(sender.data);
    });

    this.dropdowns = new SurveyDropdowns(
      this.containerTarget,
      this.element.closest('dialog'),
    );

    // Wire any "test connection" buttons (html elements) in the survey, put an
    // eye button on every masked field, and move dropdown lists out of the
    // scrolling modal box.
    this.survey.onAfterRenderQuestion.add((_sender, options) => {
      this.wireConnectionTest(options.htmlElement);
      wirePasswordReveal(options.htmlElement);
      this.dropdowns?.lift(options.question, options.htmlElement);
    });

    // Render the survey, replacing the loading spinner.
    if (this.viewTransitionsEnabled) {
      await this.renderSurveyAnimated();
    } else {
      this.renderSurvey();
    }
    if (!this.survey || !this.element.isConnected) return;

    // Handle value changes (registered after render to avoid
    // triggering dirty state from initialization/default values)
    this.survey.onValueChanged.add((_sender, options) => {
      this.handleValueChanged(options);
    });

    // onValueChanged fires only on blur; clear a stale connection-test result
    // already while the user is still typing in a field.
    this.containerTarget.addEventListener('input', this.resetTestsOnInput);
  }

  // SurveyJS renders each navigation button (Weiter/Speichern/Zurück) as
  // <input type="button" value={title} title={getTooltip()}>, and getTooltip()
  // defaults to the label when no tooltip is set — so hovering the button
  // shows a native tooltip that just repeats it. The visible label comes from
  // `value`, so returning an empty tooltip drops the redundant title="" (which
  // browsers don't show) without touching the label. The action's `tooltip`
  // property can't do this: getTooltip() is `tooltip || title`, so an empty
  // string falls back to the label.
  private suppressNavTooltips() {
    this.survey?.navigationBar.actions.forEach((action) => {
      action.getTooltip = () => '';
    });
  }

  private handleValueChanged(options: { name: string; value: unknown }) {
    // Any field edit invalidates a prior connection-test result.
    this.resetConnectionTests();

    // Dispatch custom event for other controllers to listen
    this.dispatch('valueChanged', {
      detail: {
        name: options.name,
        value: options.value,
        allData: this.survey?.data,
      },
    });
  }

  private handleComplete(data: Record<string, unknown>) {
    // Show output if target exists (standalone mode)
    if (this.hasOutputTarget) {
      this.outputTarget.innerHTML = `
        <div class="alert alert-success">
          <span>Survey completed!</span>
        </div>
        <pre class="bg-base-200 p-4 rounded-lg mt-4 overflow-auto">
          <code>${JSON.stringify(data, null, 2)}</code>
        </pre>
      `;
    }

    // Dispatch custom event
    this.dispatch('complete', { detail: { data } });
  }

  private submitForm(data: Record<string, unknown>) {
    const form = document.getElementById(this.formIdValue) as HTMLFormElement;
    if (!form) return;

    // Create single hidden field with JSON data
    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = this.fieldNameValue;
    input.value = JSON.stringify(data);
    form.appendChild(input);

    // Submit via requestSubmit so Turbo intercepts the submission
    form.requestSubmit();
  }

  // Public method to get current survey data
  getData(): Record<string, unknown> | undefined {
    return this.survey?.data;
  }

  // Public method to set survey data
  setData(data: Record<string, unknown>) {
    if (this.survey) {
      this.survey.data = data;
    }
  }

  // --- Connection test ------------------------------------------------
  // The probe runs server-side: HELIOS reaches the target (InfluxDB, SENEC,
  // Shelly, MQTT) on the same path the collectors will, and avoids the
  // browser's mixed-content/CORS limits. This only wires the button and
  // renders the result.

  private wireConnectionTest(htmlElement: HTMLElement) {
    const button = htmlElement.querySelector<HTMLButtonElement>(
      'button[data-test-target]',
    );
    // onAfterRenderQuestion can fire again for a button that survived a
    // re-render (e.g. page navigation), so guard against stacking listeners.
    if (!button || button.dataset.testWired) return;

    const status = htmlElement.querySelector<HTMLElement>(
      '.connection-test__status',
    );
    if (!status) return;

    button.dataset.testWired = 'true';
    button.addEventListener('click', () => {
      void this.runConnectionTest(button, status);
    });
  }

  // The button declares its target, check and the survey fields to submit
  // (data-test-* attributes), so this stays integration-agnostic.
  private async runConnectionTest(
    button: HTMLButtonElement,
    status: HTMLElement,
  ) {
    if (!this.survey || !this.connectionTestUrlValue) return;

    const { testTarget, testCheck, testFields } = button.dataset;
    const data = this.survey.data as Record<string, unknown>;
    const values: Record<string, unknown> = {};
    (testFields ?? '')
      .split(',')
      .filter(Boolean)
      .forEach((field) => {
        // A field may map a survey field to a differently named probe key
        // via "surveyField:probeKey" — the sensor survey prefixes its Shelly
        // fields with shelly_, while the probe expects the bare name.
        const [surveyField, probeKey = surveyField] = field.split(':');
        values[probeKey] = data[surveyField];
      });

    const labels = readLocale() === 'de' ? TEST_LABELS.de : TEST_LABELS.default;
    button.disabled = true;
    this.setConnectionStatus(
      status,
      'pending',
      CONNECTION_STATUS_ICONS.pending,
      labels.pending,
    );

    try {
      const response = await fetch(this.connectionTestUrlValue, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'application/json',
          'X-CSRF-Token': this.csrfToken(),
        },
        body: JSON.stringify({
          target: testTarget,
          check: testCheck,
          values,
        }),
      });
      const result = (await response.json()) as {
        ok: boolean;
        state?: ConnectionStatusState;
        message: string;
      };
      // A probe may answer that it could not settle the question. That is a
      // note, not a failure, so it gets its own state instead of the red one.
      const state = result.state ?? (result.ok ? 'ok' : 'error');
      this.setConnectionStatus(
        status,
        state,
        CONNECTION_STATUS_ICONS[state],
        result.message,
      );
    } catch {
      this.setConnectionStatus(
        status,
        'error',
        CONNECTION_STATUS_ICONS.error,
        labels.failed,
      );
    } finally {
      button.disabled = false;
    }
  }

  private setConnectionStatus(
    status: HTMLElement,
    state: ConnectionStatusState,
    icon: string,
    message: string,
  ) {
    status.className = `connection-test__status connection-test__status--${state}`;
    status.innerHTML = `<i class="fa-solid ${icon}" aria-hidden="true"></i><span></span>`;
    const label = status.querySelector('span');
    if (label) label.textContent = message;
  }

  private resetConnectionTests() {
    this.element
      .querySelectorAll<HTMLElement>('.connection-test__status')
      .forEach((status) => {
        // Skip statuses still in their base state — this runs on every
        // keystroke (input listener), so avoid needless DOM writes.
        if (status.childElementCount === 0) return;

        status.className = 'connection-test__status';
        status.textContent = '';
      });
  }

  private csrfToken(): string {
    return (
      document
        .querySelector('meta[name="csrf-token"]')
        ?.getAttribute('content') ?? ''
    );
  }
}

// Marks the document while a transition the survey started is running, so the
// stylesheet can hold the root snapshot still for these transitions alone and
// leave every other one to the browser (see survey.css).
//
// A class rather than a transition type: `types` arrived later than
// startViewTransition itself, so a browser that has the one need not have the
// other. Counted, because a page turn can start while the previous transition
// still runs, and the mark has to outlive both — the pseudo-elements take
// their style from the live document, frame by frame.
const TRANSITION_CLASS = 'survey-view-transition';
let openTransitions = 0;

function startSurveyTransition(update: () => void) {
  openTransitions++;
  document.documentElement.classList.add(TRANSITION_CLASS);

  const transition = document.startViewTransition(update);
  void transition.finished.finally(() => {
    openTransitions--;
    if (openTransitions === 0)
      document.documentElement.classList.remove(TRANSITION_CLASS);
  });

  return transition;
}
