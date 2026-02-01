import { Controller } from '@hotwired/stimulus';
import { config, library, dom } from '@fortawesome/fontawesome-svg-core';

// ------------------------- Add new icons here
import { faPlay } from '@fortawesome/free-solid-svg-icons/faPlay';
import { faStop } from '@fortawesome/free-solid-svg-icons/faStop';
import { faArrowsRotate } from '@fortawesome/free-solid-svg-icons/faArrowsRotate';
import { faSun } from '@fortawesome/free-solid-svg-icons/faSun';
import { faMoon } from '@fortawesome/free-solid-svg-icons/faMoon';
import { faUpRightFromSquare } from '@fortawesome/free-solid-svg-icons/faUpRightFromSquare';

// -------------------------

let faBootstrapped = false;

export default class extends Controller {
  initialize() {
    if (faBootstrapped) return;

    config.autoAddCss = false;

    // Fix flash of missing icons
    config.mutateApproach = 'sync';

    library.add(
      faPlay,
      faStop,
      faArrowsRotate,
      faSun,
      faMoon,
      faUpRightFromSquare,
    );

    dom.watch();
    faBootstrapped = true;
  }
}
