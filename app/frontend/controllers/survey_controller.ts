import { Controller } from '@hotwired/stimulus';
import { Model, surveyLocalization, FunctionFactory } from 'survey-core';
import { BorderlessDark } from 'survey-core/themes';
import { readLocale } from '../utils/preferences_cookie';
import { prefersReducedMotion } from '../utils/prefers_reduced_motion';
import { loadingSpinner } from '../utils/loading_spinner';

// SurveyJS sets these as inline CSS variables on the root element, beating
// any stylesheet rule. Merged into BorderlessDark in one applyTheme() call so
// vars we don't redefine (e.g. --sjs-general-backcolor-dark for readonly
// inputs) keep their dark-theme value.
const HELIOS_THEME = {
  ...BorderlessDark,
  cssVariables: {
    ...BorderlessDark.cssVariables,
    '--sjs-font-family': 'var(--font-sans)',
    '--sjs-font-questiontitle-family': 'var(--font-sans)',
    '--sjs-font-pagetitle-family': 'var(--font-sans)',
    '--sjs-font-surveytitle-family': 'var(--font-sans)',
    '--sjs-font-editorfont-family': 'var(--font-sans)',

    // Survey root + body sit on the page color (base-200) so the area below
    // the gold ribbon reads as a single dark slab — same tone as the page
    // behind the modal. Only the question cards lift to base-100 (raised
    // tiles) and inputs go a step lighter on top of that.
    '--sjs-general-backcolor': 'var(--color-base-200)',
    '--sjs-general-backcolor-dim': 'var(--color-base-200)',
    '--sjs-general-backcolor-dim-light': 'var(--color-base-100)',
    '--sjs-general-backcolor-dim-dark':
      'color-mix(in oklab, var(--color-base-100) 88%, white)',
    '--sjs-question-background': 'var(--color-base-100)',
    '--sjs-editor-background':
      'color-mix(in oklab, var(--color-base-100) 84%, white)',

    '--sjs-general-forecolor':
      'color-mix(in oklab, var(--color-base-content) 92%, transparent)',
    '--sjs-general-forecolor-light':
      'color-mix(in oklab, var(--color-base-content) 60%, transparent)',
    '--sjs-general-dim-forecolor': 'var(--color-base-content)',
    '--sjs-general-dim-forecolor-light':
      'color-mix(in oklab, var(--color-base-content) 70%, transparent)',

    '--sjs-primary-backcolor': 'var(--color-primary)',
    '--sjs-primary-backcolor-dark':
      'color-mix(in oklab, var(--color-primary) 88%, black)',
    '--sjs-primary-backcolor-light':
      'color-mix(in oklab, var(--color-primary) 18%, transparent)',
    '--sjs-primary-forecolor': 'var(--color-primary-content)',
    '--sjs-primary-forecolor-light':
      'color-mix(in oklab, var(--color-primary-content) 60%, transparent)',

    '--sjs-border-light':
      'color-mix(in oklab, var(--color-base-content) 18%, transparent)',
    '--sjs-border-default':
      'color-mix(in oklab, var(--color-base-content) 26%, transparent)',
    '--sjs-border-inside':
      'color-mix(in oklab, var(--color-base-content) 20%, transparent)',
    '--sjs-corner-radius': '0.625rem',
    // BorderlessDark ships with base-unit 8px which inflates every padding
    // and gap. Drop to 6px so questions feel like form fields, not posters.
    '--sjs-base-unit': '6px',

    '--sjs-special-red': 'var(--color-error)',
    '--sjs-special-red-forecolor': 'var(--color-error-content)',
    '--sjs-special-green': 'var(--color-success)',
    '--sjs-special-blue': 'var(--color-info)',
    '--sjs-special-yellow': 'var(--color-warning)',

    '--sjs-shadow-small': 'none',
    '--sjs-shadow-medium': 'none',
    '--sjs-shadow-large': 'none',
    '--sjs-shadow-inner': 'none',
  },
};

// Import Survey.JS UI (side-effect: registers UI components)
import 'survey-js-ui';

// Register German translations (Yes/No buttons, validation messages, etc.)
import 'survey-core/i18n/german';

// HELIOS uses informal "Du", but survey-core/i18n/german ships with formal
// "Sie". Patch the strings the user is most likely to see (validation +
// commonly-rendered prompts) so surveys match the rest of the UI.
Object.assign(surveyLocalization.locales.de, {
  requiredError: 'Bitte beantworte diese Frage.',
  requiredErrorInPanel: 'Bitte beantworte mindestens eine Frage.',
  requiredInAllRowsError: 'Bitte beantworte alle Fragen.',
  minSelectError: 'Bitte wähle mindestens {0} Antwort(en) aus.',
  maxSelectError: 'Bitte wähle nicht mehr als {0} Antwort(en) aus.',
  minRowCountError: 'Bitte mach in mindestens {0} Zeilen eine Eingabe.',
  textMinLength: 'Bitte gib mindestens {0} Zeichen ein.',
  textMaxLength: 'Bitte gib nicht mehr als {0} Zeichen ein.',
  textMinMaxLength: 'Bitte gib mindestens {0} und maximal {1} Zeichen ein.',
  invalidEmail: 'Bitte gib eine gültige E-Mail-Adresse ein.',
  incompletePatternError:
    'Bitte fülle den Wert aus, um dem erforderlichen Format zu entsprechen.',
  commentText: 'Bitte hinterlasse einen Kommentar',
  ratingOptionsCaption: 'Tippe hier, um zu bewerten...',
});

// Survey expression helper: true when any value of a matrix-style answer
// object equals `token`. The Software survey uses it so the Watchtower
// interval question unlocks only when a service runs on the "develop" channel.
function anyValueEquals(params: unknown[]): boolean {
  const [answers, token] = params;
  if (!answers || typeof answers !== 'object') return false;
  return Object.values(answers as Record<string, unknown>).includes(token);
}
FunctionFactory.Instance.register('anyValueEquals', anyValueEquals);

// Connection-test labels shown before the server replies (the result message
// itself comes back localized from the server). Kept here because they belong
// to a transient UI state SurveyJS never sees.
const TEST_LABELS = {
  de: { pending: 'Prüfe Verbindung…', failed: 'Prüfung fehlgeschlagen' },
  default: { pending: 'Testing connection…', failed: 'Check failed' },
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
  private inViewTransition = false;
  private lastProgress = -1;
  private readonly resetTestsOnInput = () => this.resetConnectionTests();

  async connect() {
    await this.initSurvey();
  }

  disconnect() {
    this.containerTarget.removeEventListener('input', this.resetTestsOnInput);
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
    const transition = document.startViewTransition(() => {
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

    const response = await fetch(this.urlValue);
    const surveyJson = await response.json();
    if (!this.element.isConnected) return;

    this.survey = new Model(surveyJson);
    this.survey.applyTheme(HELIOS_THEME);

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
      if (this.inViewTransition || !this.viewTransitionsEnabled) return;

      options.allowChanging = false;
      this.inViewTransition = true;
      const transition = document.startViewTransition(() => {
        sender.currentPage = options.newCurrentPage;
      });
      transition.finished.finally(() => {
        this.inViewTransition = false;
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
      options.html = `${main}<span class="mt-1 block text-sm opacity-60">${hint}</span>`;
    });

    // Load initial data if provided
    if (Object.keys(this.initialDataValue).length > 0) {
      this.survey.mergeData(this.initialDataValue);
    }

    // Auto-fill app_host from browser's address bar if not already set
    if (!this.survey.getValue('app_host')) {
      this.survey.setValue('app_host', window.location.hostname);
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

    // Wire any "test connection" buttons (html elements) in the survey.
    this.survey.onAfterRenderQuestion.add((_sender, options) => {
      this.wireConnectionTest(options.htmlElement);
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
      'fa-spinner fa-spin',
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
        message: string;
      };
      this.setConnectionStatus(
        status,
        result.ok ? 'ok' : 'error',
        result.ok ? 'fa-circle-check' : 'fa-circle-xmark',
        result.message,
      );
    } catch {
      this.setConnectionStatus(
        status,
        'error',
        'fa-circle-xmark',
        labels.failed,
      );
    } finally {
      button.disabled = false;
    }
  }

  private setConnectionStatus(
    status: HTMLElement,
    state: 'pending' | 'ok' | 'error',
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
