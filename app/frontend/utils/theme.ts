const DARK_THEMES = ['aqua'];

export function isDarkMode(): boolean {
  const theme = document.documentElement.getAttribute('data-theme') ?? '';
  return DARK_THEMES.includes(theme);
}

type Unsubscribe = () => void;

export function onThemeChange(callback: () => void): Unsubscribe {
  const observer = new MutationObserver(() => {
    callback();
  });
  observer.observe(document.documentElement, {
    attributes: true,
    attributeFilter: ['data-theme'],
  });
  return () => observer.disconnect();
}
