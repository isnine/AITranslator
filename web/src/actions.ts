import type { ActionConfig } from "./types";

export const ACTIONS: ActionConfig[] = [
  {
    id: "translate",
    name: "Translate",
    description: "Fast, fluent translation.",
    prompt:
      "Translate the input text to {{targetLanguage}} with a fluent tone. Return ONLY the translation.",
    outputType: "translate",
  },
  {
    id: "sentence-translate",
    name: "Sentence Translate",
    description: "Sentence-by-sentence pairs.",
    prompt:
      "If the input text is in {{targetLanguage}}, translate sentence by sentence to English; otherwise translate sentence by sentence to {{targetLanguage}}. Return ONLY a JSON array of objects with keys `original` and `translation`. No markdown fences.",
    outputType: "sentencePairs",
  },
  {
    id: "grammar-check",
    name: "Grammar Check",
    description: "Polished text + explanation.",
    prompt:
      "Check the grammar of the input text. Return ONLY a JSON object with keys: `polished` (corrected text), `explanation` (errors explained in {{targetLanguage}}, ❌ for severe and ⚠️ for minor), `translation` (polished text translated into {{targetLanguage}}). No markdown fences.",
    outputType: "grammarCheck",
  },
  {
    id: "polish",
    name: "Polish",
    description: "Natural phrasing, same language.",
    prompt:
      "Polish the input text to sound natural and fluent. Keep the original meaning and language. Do NOT add new information. Return ONLY the polished text.",
    outputType: "diff",
  },
  {
    id: "sentence-analysis",
    name: "Sentence Analysis",
    description: "Grammar & collocations.",
    prompt:
      "Analyze the input sentence in {{targetLanguage}} using exactly these sections:\n\n## 📚 Grammar\n- Sentence structure (clauses, parts of speech, tense/voice)\n- Key grammar patterns\n\n## ✍️ Collocations\n- Useful phrases/collocations with brief meanings and examples\n\nBe concise. No extra sections.",
    outputType: "plain",
  },
];

export const TARGET_LANGUAGES: { code: string; name: string }[] = [
  { code: "en", name: "English" },
  { code: "zh-Hans", name: "简体中文" },
  { code: "zh-Hant", name: "繁體中文" },
  { code: "ja", name: "日本語" },
  { code: "ko", name: "한국어" },
  { code: "es", name: "Español" },
  { code: "fr", name: "Français" },
  { code: "de", name: "Deutsch" },
  { code: "it", name: "Italiano" },
  { code: "pt-BR", name: "Português (BR)" },
  { code: "ru", name: "Русский" },
  { code: "ar", name: "العربية" },
];

export function languageDisplayName(code: string): string {
  return TARGET_LANGUAGES.find((l) => l.code === code)?.name ?? code;
}

export function buildInstruction(template: string, targetLanguage: string): string {
  const langName = languageDisplayName(targetLanguage);
  return template
    .replace(/\{\{targetLanguage\}\}/g, langName)
    .replace(/\{targetLanguage\}/g, langName);
}
