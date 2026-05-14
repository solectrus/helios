import '@hotwired/turbo-rails';
import.meta.glob('../channels/**/*_channel.{js,ts}', { eager: true });
import.meta.glob('../../components/**/component.css', { eager: true });

import '@/utils/setupStimulus';

// Close any open <dialog> before a Turbo visit so it doesn't briefly flash
// in the cached page snapshot used as a transition preview.
document.addEventListener('turbo:before-visit', () => {
  document
    .querySelectorAll<HTMLDialogElement>('dialog[open]')
    .forEach((dialog) => dialog.close());
});
