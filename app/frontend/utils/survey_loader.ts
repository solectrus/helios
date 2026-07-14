import type { Model, ITheme } from 'survey-core';

// Lazily loads the SurveyJS runtime (survey-core + survey-js-ui, ~360 KB gzip)
// so it is only downloaded on pages that actually render a survey — not on
// every page via the eager Stimulus controller glob. The heavy imports live
// behind dynamic import() calls that Rolldown splits into an async chunk,
// fetched the first time a survey controller connects.

export interface SurveyRuntime {
  Model: typeof Model;
  theme: ITheme;
}

// One-time init is memoised: a page may render several survey forms, but the
// runtime, localization patches and function registration must load once.
let runtimePromise: Promise<SurveyRuntime> | null = null;

export function loadSurveyRuntime(): Promise<SurveyRuntime> {
  return (runtimePromise ??= initRuntime());
}

async function initRuntime(): Promise<SurveyRuntime> {
  const [core, { BorderlessDark }] = await Promise.all([
    import('survey-core'),
    import('./survey_theme'),
    // Side-effect imports: register UI components + German translations.
    import('survey-js-ui'),
    import('survey-core/i18n/german'),
  ]);

  const { Model, surveyLocalization, FunctionFactory } = core;

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
  FunctionFactory.Instance.register('anyValueEquals', anyValueEquals);

  return { Model, theme: buildTheme(BorderlessDark) };
}

function anyValueEquals(params: unknown[]): boolean {
  const [answers, token] = params;
  if (!answers || typeof answers !== 'object') return false;
  return Object.values(answers as Record<string, unknown>).includes(token);
}

// SurveyJS sets these as inline CSS variables on the root element, beating
// any stylesheet rule. Merged into BorderlessDark in one applyTheme() call so
// vars we don't redefine (e.g. --sjs-general-backcolor-dark for readonly
// inputs) keep their dark-theme value.
function buildTheme(base: ITheme): ITheme {
  return {
    ...base,
    cssVariables: {
      ...base.cssVariables,
      '--sjs-font-family': 'var(--font-sans)',
      '--sjs-font-questiontitle-family': 'var(--font-sans)',
      '--sjs-font-pagetitle-family': 'var(--font-sans)',
      '--sjs-font-surveytitle-family': 'var(--font-sans)',
      '--sjs-font-editorfont-family': 'var(--font-sans)',

      // Every other font size in a survey is derived from this one via calc(),
      // so raising the base lifts titles, descriptions, inputs and buttons
      // together. 16px (the SurveyJS default) reads too small for forms that
      // carry this much explanatory text.
      '--sjs-font-size': '18px',

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
}
