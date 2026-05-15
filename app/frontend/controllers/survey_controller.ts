import { Controller } from '@hotwired/stimulus';
import { Model, surveyLocalization, FunctionFactory } from 'survey-core';
import { BorderlessDark } from 'survey-core/themes';
import { readLocale } from '../utils/preferences_cookie';
import { prefersReducedMotion } from '../utils/prefers_reduced_motion';

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

// Survey.JS styles are imported in application.css for correct cascade order

export default class extends Controller<HTMLElement> {
  static targets = ['container', 'output'];
  static values = {
    url: String,
    formId: String,
    fieldName: { type: String, default: 'survey_data' },
    initialData: { type: Object, default: {} },
  };

  declare containerTarget: HTMLElement;
  declare outputTarget: HTMLElement;
  declare hasOutputTarget: boolean;
  declare urlValue: string;
  declare formIdValue: string;
  declare hasFormIdValue: boolean;
  declare fieldNameValue: string;
  declare initialDataValue: Record<string, unknown>;

  private survey: Model | null = null;
  private inViewTransition = false;
  private lastProgress = -1;

  async connect() {
    await this.initSurvey();
  }

  disconnect() {
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

  private async initSurvey() {
    const response = await fetch(this.urlValue);
    const surveyJson = await response.json();
    if (!this.element.isConnected) return;

    this.survey = new Model(surveyJson);
    this.survey.applyTheme(HELIOS_THEME);

    // Built-in progress bar is replaced by a CSS underline driven by
    // --survey-progress (see updateProgress).
    this.survey.locale = readLocale();
    this.survey.showProgressBar = 'off';
    this.updateProgress();
    this.survey.onCurrentPageChanged.add(() => this.updateProgress());
    this.survey.onPageVisibleChanged.add(() => this.updateProgress());

    // Animate height changes between pages instead of snapping.
    this.survey.onCurrentPageChanging.add((sender, options) => {
      if (this.inViewTransition) return;
      if (typeof document.startViewTransition !== 'function') return;
      if (prefersReducedMotion()) return;

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

    // Render survey into container
    this.survey.render(this.containerTarget);

    // Handle value changes (registered after render to avoid
    // triggering dirty state from initialization/default values)
    this.survey.onValueChanged.add((_sender, options) => {
      this.handleValueChanged(options);
    });
  }

  private handleValueChanged(options: { name: string; value: unknown }) {
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
}
