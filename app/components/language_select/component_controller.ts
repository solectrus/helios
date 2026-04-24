import { Controller } from '@hotwired/stimulus';
import * as Turbo from '@hotwired/turbo';
import { updatePreferences } from '../../frontend/utils/preferences_cookie';

export default class extends Controller {
  select(
    event: Event & { params: { locale: string }; currentTarget: HTMLElement },
  ) {
    event.currentTarget.blur();

    updatePreferences({ locale: event.params.locale });
    Turbo.visit(window.location.href, { action: 'replace' });
  }
}
