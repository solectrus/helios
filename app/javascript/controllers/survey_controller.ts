import { Controller } from '@hotwired/stimulus';
import { Model } from 'survey-core';
import { BorderlessLight, BorderlessDark } from 'survey-core/themes';

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
  private themeObserver: MutationObserver | null = null;

  async connect() {
    await this.initSurvey();
    this.observeThemeChanges();
  }

  disconnect() {
    this.themeObserver?.disconnect();
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
    this.survey.progressBarType = 'questions';

    // Load initial data if provided
    if (this.hasInitialDataTarget) {
      const initialData = JSON.parse(
        this.initialDataTarget.textContent || '{}',
      );
      if (Object.keys(initialData).length > 0) {
        this.survey.data = initialData;
      }
    }

    // Handle value changes
    this.survey.onValueChanged.add((_sender, options) => {
      this.handleValueChanged(options);
    });

    // Handle survey completion
    this.survey.onComplete.add((sender) => {
      this.handleComplete(sender.data);
    });

    // Render survey into container
    this.survey.render(this.containerTarget);
  }

  private applyTheme() {
    if (!this.survey) return;

    const isDark = this.isDarkMode();
    this.survey.applyTheme(isDark ? BorderlessDark : BorderlessLight);
  }

  private isDarkMode(): boolean {
    const theme = document.documentElement.getAttribute('data-theme');
    // daisyUI dark themes
    return ['aqua', 'dark', 'night'].includes(theme ?? '');
  }

  private observeThemeChanges() {
    this.themeObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (
          mutation.type === 'attributes' &&
          mutation.attributeName === 'data-theme'
        ) {
          this.applyTheme();
        }
      }
    });

    this.themeObserver.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme'],
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
    // If form integration is enabled, submit the form with survey data
    if (this.hasFormIdValue) {
      this.submitForm(data);
      return;
    }

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
