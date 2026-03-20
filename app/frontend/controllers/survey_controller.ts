import { Controller } from '@hotwired/stimulus';
import { Model } from 'survey-core';
import { BorderlessLight, BorderlessDark } from 'survey-core/themes';
import { isDarkMode, onThemeChange } from '../utils/theme';

// Import Survey.JS UI (side-effect: registers UI components)
import 'survey-js-ui';

// Import Survey.JS styles
import 'survey-core/survey-core.min.css';

export default class extends Controller {
  static targets = ['container', 'output', 'initialData'];
  static values = {
    url: String,
    formId: String,
    fieldName: { type: String, default: 'survey_data' },
  };

  declare containerTarget: HTMLElement;
  declare outputTarget: HTMLElement;
  declare hasOutputTarget: boolean;
  declare initialDataTarget: HTMLScriptElement;
  declare hasInitialDataTarget: boolean;
  declare urlValue: string;
  declare formIdValue: string;
  declare hasFormIdValue: boolean;
  declare fieldNameValue: string;

  private survey: Model | null = null;
  private unsubscribeTheme: (() => void) | null = null;

  async connect() {
    await this.initSurvey();
    this.unsubscribeTheme = onThemeChange(() => this.applyTheme());
  }

  disconnect() {
    this.unsubscribeTheme?.();
    this.survey = null;
  }

  private async initSurvey() {
    // Fetch survey JSON from URL
    const response = await fetch(this.urlValue);
    const surveyJson = await response.json();

    // Create survey model from JSON
    this.survey = new Model(surveyJson);

    // Apply theme based on current mode
    this.applyTheme();

    // Configure survey
    this.survey.locale = 'en';
    this.survey.showProgressBar = 'top';
    this.survey.progressBarType = 'pages';

    // Load initial data if provided
    if (this.hasInitialDataTarget) {
      const initialData = JSON.parse(
        this.initialDataTarget.textContent || '{}',
      );
      if (Object.keys(initialData).length > 0) {
        this.survey.data = initialData;
      }
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

  private applyTheme() {
    if (!this.survey) return;

    this.survey.applyTheme(isDarkMode() ? BorderlessDark : BorderlessLight);
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

    // Submit the form
    form.submit();
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
