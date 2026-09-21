// Turns the answers of a setup scenario into the payload the survey form would
// post. Reads one JSON object on stdin, writes one on stdout:
//
//   in   { "survey": <the JSON /configuration/surveys/:id served>,
//          "answers": { <question name>: <value> } }
//   out  { "data": <the payload>, "completed": <bool>,
//          "unused": [<answer no question took>],
//          "errors": [<question and why it refused>] }
//
// SetupScenario drives this, once per answered survey. Running the real
// survey-core Model is what makes the scenario reproduce the form rather than
// imitate it: it resolves visibleIf, fills in the defaults of the questions
// the user leaves alone, refuses an incomplete page, and drops the values of
// the questions it never showed.
import { readFileSync } from 'node:fs';
import { Model } from 'survey-core';

const { survey: json, answers } = JSON.parse(readFileSync(0, 'utf8'));

const survey = new Model(json);
const unused = new Set(Object.keys(answers));

// Walk the pages the way a user does. Only the questions the current page
// shows can be answered, so an answer the survey never asks for stays behind
// in `unused` and names a question that was renamed or removed.
for (;;) {
  const page = survey.currentPage;
  if (!page) break;

  for (const question of page.questions) {
    if (question.name in answers) {
      survey.setValue(question.name, answers[question.name]);
      unused.delete(question.name);
    }
  }

  if (survey.isLastPage || !survey.nextPage()) break;
}

// The page the walk stopped on is the one that refused, so its questions carry
// the complaints. Collected before completeLastPage, which clears them.
const errors = survey.currentPage.questions
  .filter((question) => question.errors.length > 0)
  .map(
    (question) =>
      `${question.name} (${question.errors.map((error) => error.getText()).join(', ')})`,
  );

// Read the data after the completion, not before: survey-core clears the
// values of invisible questions at that point, and the form posts what is
// left (see the onComplete handler in survey_controller.ts).
const completed = survey.completeLastPage();

process.stdout.write(
  JSON.stringify({ data: survey.data, completed, unused: [...unused], errors }),
);
