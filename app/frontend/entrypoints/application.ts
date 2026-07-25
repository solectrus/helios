import '@hotwired/turbo-rails';
import.meta.glob('../channels/**/*_channel.{js,ts}', { eager: true });
import.meta.glob('../../components/**/component.css', { eager: true });

import '@/utils/setupStimulus';
import { startFrameRecovery } from '@/utils/frame_recovery';

// Retry lazy Turbo Frames whose single load attempt failed, so a page restored
// while the host is still unreachable (browser reopening tabs after a reboot)
// doesn't keep spinning until the user reloads by hand.
startFrameRecovery();

// Close any open <dialog> before a Turbo visit so it doesn't briefly flash
// in the cached page snapshot used as a transition preview.
document.addEventListener('turbo:before-visit', () => {
  document
    .querySelectorAll<HTMLDialogElement>('dialog[open]')
    .forEach((dialog) => dialog.close());
});
