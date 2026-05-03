import type { GrammarCheckResult, SentencePair } from "./types";

function stripFences(text: string): string {
  const trimmed = text.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)\s*```$/i;
  const m = trimmed.match(fence);
  return (m ? m[1] : trimmed).trim();
}

function extractJSONSlice(text: string, opener: "{" | "["): string | null {
  const start = text.indexOf(opener);
  if (start === -1) return null;
  const closer = opener === "{" ? "}" : "]";
  let depth = 0;
  let inString = false;
  let escape = false;
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escape) escape = false;
      else if (ch === "\\") escape = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') inString = true;
    else if (ch === opener) depth++;
    else if (ch === closer) {
      depth--;
      if (depth === 0) return text.slice(start, i + 1);
    }
  }
  return null;
}

export function parseSentencePairs(text: string): SentencePair[] {
  const cleaned = stripFences(text);
  const candidates = [cleaned, extractJSONSlice(cleaned, "[")].filter(Boolean) as string[];
  for (const c of candidates) {
    try {
      const json = JSON.parse(c);
      if (Array.isArray(json)) {
        return json
          .map((item) => ({
            original: String(item.original ?? item.source ?? ""),
            translation: String(item.translation ?? item.target ?? ""),
          }))
          .filter((p) => p.original || p.translation);
      }
    } catch {
      // continue
    }
  }
  return [];
}

export function parseGrammarCheck(text: string): GrammarCheckResult | null {
  const cleaned = stripFences(text);
  const candidates = [cleaned, extractJSONSlice(cleaned, "{")].filter(Boolean) as string[];
  for (const c of candidates) {
    try {
      const json = JSON.parse(c);
      return {
        polished: String(json.polished ?? ""),
        explanation: String(json.explanation ?? ""),
        translation: String(json.translation ?? ""),
      };
    } catch {
      // continue
    }
  }
  return null;
}
