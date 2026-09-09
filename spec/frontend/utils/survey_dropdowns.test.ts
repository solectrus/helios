import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { SurveyDropdowns } from '@/utils/survey_dropdowns';

// The popup model SurveyJS hands out for a dropdown question, reduced to what
// SurveyDropdowns touches.
function fakeQuestion() {
  return {
    dropdownListModel: {
      popupModel: {
        getTargetCallback: undefined as (() => HTMLElement) | undefined,
      },
    },
  };
}

// The nesting SurveyJS renders for a dropdown: the list sits in a wrapper next
// to the field, both inside the question.
function renderQuestion(selected = 'Europe/Berlin') {
  const question = document.createElement('div');
  question.className = 'sd-question';
  question.innerHTML = `
    <div class="sv-dropdown_select-wrapper">
      <div class="sd-formbox sd-dropdown"><input type="text" value="${selected}"></div>
      <div><div class="sv-popup"><div class="sd-selectlist">
        <div class="sd-selectlist__item sd-selectlist__item--selected">${selected}</div>
      </div></div></div>
    </div>`;
  document.querySelector('.sd-root-modern')!.append(question);

  return question;
}

describe('SurveyDropdowns', () => {
  let dropdowns: SurveyDropdowns;

  beforeEach(() => {
    document.body.innerHTML = `
      <dialog open>
        <div class="modal-box">
          <div data-survey-target="container">
            <div class="sd-root-modern" style="--sjs-primary: gold"></div>
          </div>
        </div>
      </dialog>`;

    dropdowns = new SurveyDropdowns(
      container(),
      document.querySelector('dialog'),
    );
  });

  afterEach(() => {
    document.body.innerHTML = '';
    vi.restoreAllMocks();
  });

  function container() {
    return document.querySelector<HTMLElement>(
      '[data-survey-target=container]',
    )!;
  }

  function host() {
    return document.querySelector<HTMLElement>('dialog > .sd-root-modern');
  }

  it('moves the list out of the scrolling box, next to the dialog', () => {
    const question = renderQuestion();

    dropdowns.lift(fakeQuestion(), question);

    expect(question.querySelector('.sv-popup')).toBeNull();
    expect(host()!.querySelector('.sv-popup')).not.toBeNull();
    expect(document.querySelector('.modal-box .sv-popup')).toBeNull();
  });

  it('carries the theme of the survey root over to the host', () => {
    dropdowns.lift(fakeQuestion(), renderQuestion());

    expect(host()!.className).toContain('sd-root-modern');
    expect(host()!.style.getPropertyValue('--sjs-primary')).toBe('gold');
  });

  it('keeps the list anchored to its own field', () => {
    const question = renderQuestion();
    const popup = fakeQuestion();

    dropdowns.lift(popup, question);

    expect(popup.dropdownListModel.popupModel.getTargetCallback!()).toBe(
      question.querySelector('.sd-dropdown'),
    );
  });

  it('ignores questions without a list, such as text fields', () => {
    const question = document.createElement('div');
    question.innerHTML = '<input type="text">';

    dropdowns.lift({}, question);

    expect(host()).toBeNull();
  });

  it('drops a list whose question is gone, so re-renders do not pile up', () => {
    const first = renderQuestion();
    dropdowns.lift(fakeQuestion(), first);
    first.remove();

    dropdowns.lift(fakeQuestion(), renderQuestion());

    expect(host()!.querySelectorAll('.sv-popup')).toHaveLength(1);
  });

  it('takes its lists along when the survey goes', () => {
    dropdowns.lift(fakeQuestion(), renderQuestion());

    dropdowns.release();

    expect(host()).toBeNull();
    expect(document.querySelector('.sv-popup')).toBeNull();
  });
});
