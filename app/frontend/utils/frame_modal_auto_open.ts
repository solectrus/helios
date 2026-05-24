// Wire a Turbo Frame so that its containing <dialog> opens as soon as the
// frame starts fetching (so the user sees the spinner immediately instead
// of waiting for the response) and re-opens on frame-load as a fallback.
//
// Returns a teardown function that detaches both listeners.
export interface FrameModalAutoOpenOptions {
  frame: HTMLElement;
  open: () => void;
  onFetchStart?: () => void;
}

export function attachFrameModalAutoOpen({
  frame,
  open,
  onFetchStart,
}: FrameModalAutoOpenOptions): () => void {
  const handleFetchStart = (event: Event) => {
    // Only react to navigation of the frame itself, not form submissions
    // bubbling up from inside the modal.
    if (event.target !== frame) return;
    onFetchStart?.();
    open();
  };

  const handleFrameLoad = () => open();

  frame.addEventListener('turbo:before-fetch-request', handleFetchStart);
  frame.addEventListener('turbo:frame-load', handleFrameLoad);

  return () => {
    frame.removeEventListener('turbo:before-fetch-request', handleFetchStart);
    frame.removeEventListener('turbo:frame-load', handleFrameLoad);
  };
}
