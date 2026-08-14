import type { Model, ITheme } from 'survey-core';

// Lazily loads the SurveyJS runtime (survey-core + survey-js-ui, ~370 KB gzip)
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

  const { Model, surveyLocalization } = core;

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

  return { Model, theme: buildTheme(BorderlessDark) };
}

// SurveyJS sets these as inline CSS variables on the root element, beating any
// stylesheet rule. Merged into BorderlessDark in one applyTheme() call so vars
// we don't redefine (e.g. --sjs2-color-bg-basic-primary-disabled) keep their
// dark-theme value.
//
// The v3 tokens form a graph: most component tokens derive from a handful of
// roots, so overriding a root (e.g. --sjs2-color-project-brand-600) carries
// through. BorderlessDark pins some of those derivations to literal colors,
// which is why a few tokens below look redundant but are not.
function buildTheme(base: ITheme): ITheme {
  // Fill of anything the user types or ticks into: text fields, and the empty
  // state of radios and checkboxes. A notch lighter than the question card so
  // an empty control still reads as a control.
  const inputFill = 'color-mix(in oklab, var(--color-base-100) 84%, white)';

  return {
    ...base,
    cssVariables: {
      ...base.cssVariables,
      // Every component font family derives from this one.
      '--sjs2-typography-font-family-text': 'var(--font-sans)',

      // Every font size in a survey derives from this half-unit via calc(), so
      // raising it lifts titles, descriptions, inputs and buttons together. The
      // SurveyJS default of 8px (= 16px base) reads too small for forms that
      // carry this much explanatory text; 9px gives an 18px base.
      '--sjs2-base-unit-font-size': '9px',
      '--sjs2-base-unit-line-height': '9px',

      // BorderlessDark ships with base-unit 8px which inflates every padding
      // and gap. Drop to 6px so questions feel like form fields, not posters.
      '--sjs2-base-unit-size': '6px',
      '--sjs2-base-unit-spacing': '6px',
      '--sjs2-base-unit-radius': '0.625rem',

      // Gaps around and between the question cards. survey-core asks for 30px
      // each, which costs about 100px on a form of five questions. A 1280x800
      // laptop must show a whole page without scrolling, so both drop to 16px.
      '--sjs2-layout-component-page-box-gap-vertical': '1rem',
      '--sjs2-layout-component-survey-box-gap-vertical': '1rem',

      // Gap between a question title and its input.
      '--sjs2-layout-component-question-box-gap-vertical': '0.5rem',

      // survey-core insets the page content by another 30px on top of the
      // padding .sd-page already carries. Drop it, so the cards, the page
      // heading and the action bar all line up on one edge.
      '--sjs2-layout-component-page-content-area-padding-horizontal': '0',
      '--sjs2-layout-component-page-header-padding-horizontal': '0',

      // The two headings above a form scale off the 18px base and grow to
      // 31.5px and 24.75px. That is more weight than a settings dialog needs,
      // and it costs height on every form, so both come down a step.
      '--sjs2-typography-font-size-component-survey-header-title': '1.5rem',
      '--sjs2-typography-line-height-component-survey-header-title': '2rem',
      // The heading picks up the gold of the rule below it.
      '--sjs2-color-component-survey-header-default-title':
        'var(--color-primary)',
      '--sjs2-typography-font-size-component-page-title': '1.25rem',
      '--sjs2-typography-line-height-component-page-title': '1.75rem',

      // Explanatory text supports what it belongs to rather than competing
      // with it, so it sits below the 18px body. survey-core sizes all of it
      // like the body and separates it by color alone, which leaves a form of
      // nothing but 18px lines. Two steps instead of one, because the text
      // under a heading of 24px or 20px carries the whole modal or the whole
      // page, while the text under an 18px question title carries one field.
      '--sjs2-typography-font-size-component-survey-header-description': '1rem',
      '--sjs2-typography-line-height-component-survey-header-description':
        '1.5rem',
      '--sjs2-typography-font-size-component-page-description': '1rem',
      '--sjs2-typography-line-height-component-page-description': '1.5rem',
      // The question step is the whole 14px tier: the prose blocks, the hint
      // under a choice label and the connection-test row read these two
      // values back out of the CSS instead of carrying sizes of their own.
      '--sjs2-typography-font-size-component-question-description': '0.875rem',
      '--sjs2-typography-line-height-component-question-description':
        '1.3125rem',

      // Survey root + body sit on the page color (base-200) so the area below
      // the gold ribbon reads as a single dark slab, same tone as the page
      // behind the modal. Only the question cards lift to base-100 (raised
      // tiles) and inputs go a step lighter on top of that.
      '--sjs2-color-utility-body': 'var(--color-base-200)',
      '--sjs2-color-utility-surface-survey': 'var(--color-base-200)',
      '--sjs2-color-utility-sheet': 'var(--color-base-200)',
      '--sjs2-color-bg-basic-primary': 'var(--color-base-200)',
      '--sjs2-color-bg-basic-tertiary': 'var(--color-base-200)',
      '--sjs2-color-bg-basic-secondary': 'var(--color-base-100)',
      '--sjs2-color-bg-basic-secondary-dim':
        'color-mix(in oklab, var(--color-base-100) 88%, white)',
      // Questions without a nested panel take the "simple" panel token, the
      // matrix and composite ones take the plain panel token. Both are cards.
      '--sjs2-color-component-panel-simple-default-bg': 'var(--color-base-100)',
      '--sjs2-color-component-panel-default-bg': 'var(--color-base-100)',
      '--sjs2-color-component-formbox-default-bg': inputFill,
      '--sjs2-color-component-radio-false-default-bg': inputFill,
      '--sjs2-color-component-checkbox-false-default-bg': inputFill,
      // A boolean question is a track with a sliding thumb. The track is a
      // field, so it takes the field fill, and the thumb rides on it in the
      // card color. Both default a step darker, which sinks the track into
      // the card and pushes the thumb below it.
      '--sjs2-color-component-boolean-default-bg': inputFill,
      '--sjs2-color-component-boolean-item-true-default-bg':
        'var(--color-base-100)',

      // fg-basic-secondary (descriptions, placeholders) derives from this at
      // 60% opacity, matching the muted tone the rest of the UI uses.
      '--sjs2-color-fg-basic-primary':
        'color-mix(in oklab, var(--color-base-content) 92%, transparent)',

      '--sjs2-color-project-brand-600': 'var(--color-primary)',
      '--sjs2-color-bg-brand-primary-dim':
        'color-mix(in oklab, var(--color-primary) 88%, black)',
      '--sjs2-color-bg-brand-secondary':
        'color-mix(in oklab, var(--color-primary) 18%, transparent)',
      '--sjs2-color-fg-brand-on-primary': 'var(--color-primary-content)',

      '--sjs2-color-border-basic-secondary':
        'color-mix(in oklab, var(--color-base-content) 18%, transparent)',
      '--sjs2-color-border-basic-secondary-overlay':
        'color-mix(in oklab, var(--color-base-content) 20%, transparent)',
      '--sjs2-color-component-input-default-line':
        'color-mix(in oklab, var(--color-base-content) 26%, transparent)',

      '--sjs2-color-bg-alert-primary': 'var(--color-error)',
      '--sjs2-color-fg-alert-on-primary': 'var(--color-error-content)',
      '--sjs2-color-bg-positive-primary': 'var(--color-success)',
      '--sjs2-color-bg-note-primary': 'var(--color-info)',
      '--sjs2-color-bg-warning-primary': 'var(--color-warning)',

      // Surfaces are separated by tone, not by elevation.
      '--sjs2-border-effect-surface-default': '0 0 0 0 transparent',
      '--sjs2-border-effect-floating-default': '0 0 0 0 transparent',
    },
  };
}
