import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { wirePasswordReveal } from '@/utils/survey_password_reveal';

// What SurveyJS renders for a masked text question: the input sits in a
// wrapper of its own inside the question.
function renderQuestion(type = 'password') {
  const question = document.createElement('div');
  question.className = 'sd-question';
  question.innerHTML = `<div class="sd-text__content"><input type="${type}" class="sd-input" value="s3cret"></div>`;
  document.body.append(question);

  return question;
}

function button(question: HTMLElement) {
  return question.querySelector<HTMLButtonElement>('.password-reveal');
}

function input(question: HTMLElement) {
  return question.querySelector<HTMLInputElement>('input')!;
}

describe('wirePasswordReveal', () => {
  beforeEach(() => {
    document.body.innerHTML = '';
  });

  afterEach(() => {
    document.cookie = 'preferences=; max-age=0; path=/';
  });

  it('puts a button on a masked field, and leaves the value masked', () => {
    const question = renderQuestion();

    wirePasswordReveal(question);

    expect(button(question)).not.toBeNull();
    expect(input(question).type).toBe('password');
    expect(input(question).value).toBe('s3cret');
  });

  it('uncovers the value on a click, and masks it again on the next', () => {
    const question = renderQuestion();
    wirePasswordReveal(question);

    button(question)!.click();
    expect(input(question).type).toBe('text');
    expect(button(question)!.getAttribute('aria-pressed')).toBe('true');

    button(question)!.click();
    expect(input(question).type).toBe('password');
    expect(button(question)!.getAttribute('aria-pressed')).toBe('false');
  });

  it('names what the next click does, and swaps the icon along with it', () => {
    const question = renderQuestion();
    wirePasswordReveal(question);

    expect(button(question)!.getAttribute('aria-label')).toBe('Show password');
    expect(question.querySelector('i')!.className).toContain('fa-eye');

    button(question)!.click();
    expect(button(question)!.getAttribute('aria-label')).toBe('Hide password');
    expect(question.querySelector('i')!.className).toContain('fa-eye-slash');
  });

  it('speaks the language of the user', () => {
    document.cookie = `preferences=${encodeURIComponent(JSON.stringify({ locale: 'de' }))}; path=/`;
    const question = renderQuestion();

    wirePasswordReveal(question);

    expect(button(question)!.getAttribute('aria-label')).toBe(
      'Passwort anzeigen',
    );
  });

  it('keeps the caret at the end, so the field can be typed on', () => {
    const question = renderQuestion();
    wirePasswordReveal(question);

    button(question)!.click();

    expect(input(question).selectionStart).toBe('s3cret'.length);
  });

  it('adds no second button when the question renders again', () => {
    const question = renderQuestion();

    wirePasswordReveal(question);
    wirePasswordReveal(question);

    expect(question.querySelectorAll('.password-reveal')).toHaveLength(1);
  });

  it('keeps password managers off a field asking for a foreign secret', () => {
    const question = renderQuestion();

    wirePasswordReveal(question);

    expect(input(question).autocomplete).toBe('off');
    expect(input(question).getAttribute('data-bwignore')).toBe('true');
    expect(input(question).getAttribute('data-1p-ignore')).toBe('true');
    expect(input(question).getAttribute('data-lpignore')).toBe('true');
    expect(input(question).getAttribute('data-form-type')).toBe('other');
  });

  it('leaves a field that holds no secret alone', () => {
    const question = renderQuestion('text');

    wirePasswordReveal(question);

    expect(button(question)).toBeNull();
  });
});
