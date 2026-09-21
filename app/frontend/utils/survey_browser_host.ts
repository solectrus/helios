import type { Model, Question } from 'survey-core';

// Marker a survey carries to have the host of the address bar offered as the
// answer to one of its questions, for as long as another answer allows it. The
// server sets it (see Surveys::ReverseProxy::Survey), and the survey controller
// strips it from the JSON before the model is built.
export type BrowserHostOffer = {
  question: string;
  while: { question: string; values: string[] };
};

// Offer `host` as the answer to the question the marker names, while the answer
// it depends on is one of the listed values.
//
// The offer is made once that condition holds and the field is still empty, and
// it is withdrawn once the condition drops. A survey that asks for both in one
// run would otherwise keep a value the page put there as the answer to a
// question it no longer fits. Only the offered value is withdrawn: a value the
// user typed over it stays.
//
// The question can refuse the host outright, which the address field does for
// an address that names the machine to itself alone. Its rule is asked
// beforehand, because filling a field and validating afterwards would mark a
// value the user never typed as an error.
export function wireBrowserHostOffer(
  survey: Model,
  offer: BrowserHostOffer,
  host: string,
) {
  const question = survey.getQuestionByName(offer.question);
  if (!question) return;

  let offered: string | null = null;

  const apply = () => {
    const allowed = offer.while.values.includes(
      String(survey.getValue(offer.while.question) ?? ''),
    );

    if (allowed && !question.value && accepts(question, host)) {
      question.value = host;
      offered = host;
    } else if (!allowed && offered !== null && question.value === offered) {
      question.clearValue();
      offered = null;
    }
  };

  apply();
  survey.onValueChanged.add((_sender, options) => {
    if (options.name === offer.while.question) apply();
  });
}

// Whether a question would take a value, judged by the regex rules it carries
// and without assigning anything. Used where a value is offered rather than
// typed, so an offer the question refuses is simply not made.
function accepts(question: Question, value: string): boolean {
  return question.validators.every((validator) => {
    const { regex, caseInsensitive } = validator as {
      regex?: string;
      caseInsensitive?: boolean;
    };

    return !regex || new RegExp(regex, caseInsensitive ? 'i' : '').test(value);
  });
}
