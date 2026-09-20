import { readLocale } from './preferences_cookie';

// The button says what a click does next, so it swaps along with the field.
const LABELS = {
  de: { show: 'Text anzeigen', hide: 'Text verbergen' },
  default: { show: 'Show text', hide: 'Hide text' },
};

const ICONS = { show: 'fa-eye', hide: 'fa-eye-slash' };

// A survey asks for the credentials of a foreign service, never for the ones
// of HELIOS itself, so every offer a password manager makes here is wrong,
// and its inline icon covers the eye button.
//
// HTML has no token for this. `autocomplete` names what a field holds
// (`current-password`, `new-password`), but the only way to decline is
// `autocomplete="off"`, and the specification lets a password manager ignore
// it. So each vendor reads an opt-out attribute of its own, and we set all of
// them next to the standard one.
const PASSWORD_MANAGER_OPT_OUT = {
  'data-bwignore': 'true', // Bitwarden
  'data-1p-ignore': 'true', // 1Password
  'data-lpignore': 'true', // LastPass
  'data-form-type': 'other', // Dashlane
};

// Every secret a survey asks for renders masked (see Surveys::Base), which
// hides typos as well: a token is long, arrives through a clipboard that may
// have clipped it, and a password has to be typed into a device afterwards.
// So each masked field gets an eye button that uncovers it while the user
// looks at it.
//
// The field keeps its value throughout, because only the input type changes.
// SurveyJS neither renders nor reads that attribute after it set it up, so it
// stays out of the survey data.
export function wirePasswordReveal(htmlElement: HTMLElement) {
  const input = htmlElement.querySelector<HTMLInputElement>(
    'input[type="password"]',
  );
  // A question can render again (page navigation, a condition), which brings
  // back the plain input, but it can also survive with the button already on
  // it. Marking the input tells the two apart.
  if (!input || input.dataset.revealWired) return;

  const field = input.parentElement;
  if (!field) return;

  input.dataset.revealWired = 'true';
  input.autocomplete = 'off';
  for (const [name, value] of Object.entries(PASSWORD_MANAGER_OPT_OUT))
    input.setAttribute(name, value);
  input.classList.add('password-reveal__input');

  const button = document.createElement('button');
  button.type = 'button';
  // The eye carries the meaning, so the icon is the label and gets a name of
  // its own rather than a second, visible one.
  button.className = 'password-reveal';
  button.innerHTML = '<i aria-hidden="true" class="fa-solid"></i>';

  const apply = (masked: boolean) => {
    const labels = readLocale() === 'de' ? LABELS.de : LABELS.default;
    const state = masked ? 'show' : 'hide';

    input.type = masked ? 'password' : 'text';
    button.setAttribute('aria-label', labels[state]);
    button.title = labels[state];
    button.setAttribute('aria-pressed', String(!masked));
    button
      .querySelector('i')
      ?.setAttribute('class', `fa-solid ${ICONS[state]}`);
  };

  apply(true);

  // The caret would otherwise land at the start of the value, which reads as
  // a jump for a field the user is in the middle of.
  button.addEventListener('click', () => {
    const masked = input.type !== 'password';
    apply(masked);
    input.focus();
    input.setSelectionRange(input.value.length, input.value.length);
  });

  field.append(button);
}
