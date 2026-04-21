import { describe, it, expect, beforeEach } from 'vitest';
import { readLocale, updatePreferences } from '@/utils/preferences_cookie';

function clearCookies() {
  document.cookie.split(';').forEach((c) => {
    const name = c.split('=')[0].trim();
    document.cookie = `${name}=; path=/; max-age=0`;
  });
}

function readCookieValue(name: string): string | null {
  const match = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1]) : null;
}

describe('preferences_cookie', () => {
  beforeEach(() => {
    clearCookies();
    document.documentElement.lang = '';
  });

  describe('readLocale', () => {
    it('returns locale from cookie when present', () => {
      updatePreferences({ locale: 'de' });

      expect(readLocale()).toBe('de');
    });

    it('falls back to <html lang> when cookie has no locale', () => {
      document.documentElement.lang = 'de';

      expect(readLocale()).toBe('de');
    });

    it('falls back to "en" when no locale is available', () => {
      expect(readLocale()).toBe('en');
    });

    it('ignores malformed cookie content', () => {
      document.cookie = 'preferences=%7Bnot-json; path=/';

      expect(readLocale()).toBe('en');
    });
  });

  describe('updatePreferences', () => {
    it('writes a fresh cookie when none exists', () => {
      updatePreferences({ expert_mode: true });

      expect(JSON.parse(readCookieValue('preferences')!)).toEqual({
        expert_mode: true,
      });
    });

    it('merges with existing preferences', () => {
      updatePreferences({ locale: 'de' });
      updatePreferences({ expert_mode: true });

      expect(JSON.parse(readCookieValue('preferences')!)).toEqual({
        locale: 'de',
        expert_mode: true,
      });
    });

    it('overwrites existing keys', () => {
      updatePreferences({ locale: 'de' });
      updatePreferences({ locale: 'en' });

      expect(JSON.parse(readCookieValue('preferences')!)).toEqual({
        locale: 'en',
      });
    });
  });
});
