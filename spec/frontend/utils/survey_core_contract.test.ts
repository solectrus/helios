import { describe, it, expect } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { BorderlessDark } from 'survey-core/themes';

// HELIOS drives survey-core by name: survey_loader hands applyTheme a list of
// custom properties to override, and survey.css reads some of them back and
// targets survey-core's own classes. Both fail quietly. A property survey-core
// renamed is set but read by nobody, and the form drops back to the stock dark
// palette. A class it renamed matches nothing, and the rule is skipped. These
// specs turn both into a failing build, here and on the next survey-core bump.

const require_ = createRequire(import.meta.url);
const root = path.resolve(import.meta.dirname, '../../..');

const read = (relativePath: string) =>
  fs.readFileSync(path.join(root, relativePath), 'utf8');

const ourCss = read('app/frontend/styles/survey.css');
const ourLoader = read('app/frontend/utils/survey_loader.ts');

// The stylesheet is the only entry the package exports by a path we need, so
// the package directory is derived from it rather than resolved on its own.
const surveyCore = path.dirname(
  require_.resolve('survey-core/survey-core.min.css'),
);
const shippedCss = fs.readFileSync(
  path.join(surveyCore, 'survey-core.min.css'),
  'utf8',
);
const shippedJs = fs.readFileSync(
  path.join(surveyCore, 'survey.core.min.js'),
  'utf8',
);

const themeVariables = new Set(Object.keys(BorderlessDark.cssVariables));

// Classes HELIOS injects itself, which therefore cannot appear upstream.
// `sd-hint` comes from the markdown hook in survey_controller.
const OWN_CLASSES = ['sd-hint'];

const unique = (matches: RegExpMatchArray | null) => [
  ...new Set(matches ?? []),
];

const propertiesIn = (source: string) =>
  unique(source.match(/--s(?:js2?|d)-[a-zA-Z0-9_-]*/g));

const knownProperty = (property: string) =>
  shippedCss.includes(property) || themeVariables.has(property);

describe.each([
  ['app/frontend/styles/survey.css', ourCss],
  ['app/frontend/utils/survey_loader.ts', ourLoader],
])('%s custom properties', (_name, source) => {
  const properties = propertiesIn(source);

  it('names properties survey-core still defines', () => {
    expect(properties.filter((p) => !knownProperty(p))).toEqual([]);
  });

  it('finds properties to check', () => {
    expect(properties.length).toBeGreaterThan(0);
  });
});

describe('survey.css selectors', () => {
  const classes = unique(ourCss.match(/\.s(?:d|v|js)[a-zA-Z0-9_-]*/g)).map(
    (selector) => selector.slice(1),
  );

  it('targets classes survey-core still renders', () => {
    const unknown = classes.filter(
      (name) =>
        !OWN_CLASSES.includes(name) &&
        !shippedCss.includes(name) &&
        !shippedJs.includes(name),
    );

    expect(unknown).toEqual([]);
  });

  it('finds classes to check', () => {
    expect(classes.length).toBeGreaterThan(0);
  });
});
