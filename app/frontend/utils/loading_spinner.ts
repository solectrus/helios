// Clones the shared loading-spinner <template> rendered once in the layout,
// so the spinner markup lives in a single ViewComponent (LoadingSpinner) for
// both server- and client-side rendering.
export function loadingSpinner(): DocumentFragment {
  const template = document.getElementById('loading-spinner');
  if (!(template instanceof HTMLTemplateElement))
    throw new Error('Missing <template id="loading-spinner"> in the layout');

  return template.content.cloneNode(true) as DocumentFragment;
}
