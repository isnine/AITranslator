import type { AppSettings } from "./types";

const KEY = "tlingo-web-settings-v2";

const DEFAULTS: AppSettings = {
  model: "gpt-5.4-nano",
  targetLanguage: "zh-Hans",
};

export const AVAILABLE_MODELS: { id: string; name: string }[] = [
  { id: "gpt-5.4-nano", name: "GPT-5.4 Nano" },
  { id: "gpt-5.4-mini", name: "GPT-5.4 Mini" },
  { id: "gpt-5-mini", name: "GPT-5 Mini" },
  { id: "gpt-5-nano", name: "GPT-5 Nano" },
  { id: "gpt-4o-mini", name: "GPT-4o Mini" },
  { id: "gpt-4.1-mini", name: "GPT-4.1 Mini" },
];

export function loadSettings(): AppSettings {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...DEFAULTS };
    const parsed = JSON.parse(raw) as Partial<AppSettings>;
    return { ...DEFAULTS, ...parsed };
  } catch {
    return { ...DEFAULTS };
  }
}

export function saveSettings(s: AppSettings): void {
  localStorage.setItem(KEY, JSON.stringify(s));
}
