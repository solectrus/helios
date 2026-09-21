import { describe, it, expect } from 'vitest';
import { Model } from 'survey-core';
import {
  wireBrowserHostOffer,
  type BrowserHostOffer,
} from '@/utils/survey_browser_host';

const OFFER: BrowserHostOffer = {
  question: 'app_host',
  while: { question: 'mode', values: ['none'] },
};

// Mirrors the reverse-proxy form: the mode is asked first, the address second,
// and the address field refuses a loopback name.
function buildSurvey() {
  return new Model({
    pages: [
      {
        elements: [
          {
            type: 'radiogroup',
            name: 'mode',
            choices: ['none', 'internal', 'external'],
          },
        ],
      },
      {
        elements: [
          {
            type: 'text',
            name: 'app_host',
            validators: [
              {
                type: 'regex',
                regex: '^(?!localhost$).+$',
                caseInsensitive: true,
              },
            ],
          },
        ],
      },
    ],
  });
}

describe('wireBrowserHostOffer', () => {
  it('offers the host while the condition holds', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');

    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    expect(survey.getValue('app_host')).toBe('solectrus.fritz.box');
  });

  // The form asks for the mode before it asks for the address, so an offer
  // waits for that answer rather than guessing which one it will be.
  it('makes no offer while the condition is unanswered', () => {
    const survey = buildSurvey();

    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    expect(survey.getValue('app_host')).toBeUndefined();
  });

  it('offers the host once the condition is answered', () => {
    const survey = buildSurvey();
    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    survey.setValue('mode', 'none');

    expect(survey.getValue('app_host')).toBe('solectrus.fritz.box');
  });

  it('makes no offer while the condition does not hold', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'internal');

    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    expect(survey.getValue('app_host')).toBeUndefined();
  });

  // Behind a proxy the field takes a domain, and the address bar names it
  // nowhere. An offer left standing would answer a mandatory question with the
  // one value it must not hold.
  it('withdraws the offer once the condition drops', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');
    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    survey.setValue('mode', 'internal');

    expect(survey.getValue('app_host')).toBeUndefined();
  });

  it('offers the host again when the condition returns', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');
    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    survey.setValue('mode', 'internal');
    survey.setValue('mode', 'none');

    expect(survey.getValue('app_host')).toBe('solectrus.fritz.box');
  });

  it('keeps a value the user typed over the offer', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');
    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    survey.setValue('app_host', 'solar.example.com');
    survey.setValue('mode', 'internal');

    expect(survey.getValue('app_host')).toBe('solar.example.com');
  });

  it('keeps a value that was already stored', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');
    survey.setValue('app_host', 'solar.example.com');

    wireBrowserHostOffer(survey, OFFER, 'solectrus.fritz.box');

    expect(survey.getValue('app_host')).toBe('solar.example.com');
  });

  it('makes no offer the question refuses', () => {
    const survey = buildSurvey();
    survey.setValue('mode', 'none');

    wireBrowserHostOffer(survey, OFFER, 'localhost');

    expect(survey.getValue('app_host')).toBeUndefined();
  });

  it('does nothing when the survey has no such question', () => {
    const survey = buildSurvey();

    wireBrowserHostOffer(
      survey,
      { ...OFFER, question: 'nowhere' },
      'solectrus.fritz.box',
    );

    expect(survey.getValue('app_host')).toBeUndefined();
  });
});
