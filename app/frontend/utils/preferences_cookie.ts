const COOKIE_NAME = 'preferences';
const MAX_AGE = 60 * 60 * 24 * 365; // 1 year

interface Preferences {
  theme?: string;
  expert_mode?: boolean;
  show_all_sensors?: boolean;
  locale?: string;
  [key: string]: string | boolean | undefined;
}

function readPreferences(): Preferences {
  const match = document.cookie.match(
    new RegExp(`(?:^|; )${COOKIE_NAME}=([^;]*)`),
  );
  if (!match) return {};

  try {
    return JSON.parse(decodeURIComponent(match[1]));
  } catch {
    return {};
  }
}

export function readLocale(): string {
  return readPreferences().locale ?? 'en';
}

export function updatePreferences(updates: Partial<Preferences>) {
  const current = readPreferences();
  const merged = { ...current, ...updates };
  const value = encodeURIComponent(JSON.stringify(merged));
  document.cookie = `${COOKIE_NAME}=${value}; path=/; SameSite=Lax; max-age=${MAX_AGE}`;
}
