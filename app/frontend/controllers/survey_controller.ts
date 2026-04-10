import { Controller } from '@hotwired/stimulus';
import { Model } from 'survey-core';
import { BorderlessDark } from 'survey-core/themes';
import { readLocale } from '../utils/preferences_cookie';

// Import Survey.JS UI (side-effect: registers UI components)
import 'survey-js-ui';

// Survey.JS styles are imported in application.css for correct cascade order

export default class extends Controller {
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

  async connect() {
    await this.initSurvey();
  }

  disconnect() {
    this.survey = null;
  }

  private async initSurvey() {
    // Fetch survey JSON from URL
    const response = await fetch(this.urlValue);
    const surveyJson = await response.json();

    // Create survey model from JSON
    this.survey = new Model(surveyJson);
    this.survey.applyTheme(BorderlessDark);

    // Configure survey
    this.survey.locale = readLocale();
    this.survey.showProgressBar = 'top';
    this.survey.progressBarType = 'pages';

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
