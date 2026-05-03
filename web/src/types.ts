export type ActionId =
  | "translate"
  | "sentence-translate"
  | "grammar-check"
  | "polish"
  | "sentence-analysis";

export type OutputType =
  | "translate"
  | "sentencePairs"
  | "grammarCheck"
  | "diff"
  | "plain";

export interface ActionConfig {
  id: ActionId;
  name: string;
  description: string;
  prompt: string;
  outputType: OutputType;
}

export interface AppSettings {
  model: string;
  targetLanguage: string;
}

export interface SentencePair {
  original: string;
  translation: string;
}

export interface GrammarCheckResult {
  polished: string;
  explanation: string;
  translation: string;
}

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export interface TranslationHistoryEntry {
  id: string;
  createdAt: string;
  actionId: string;
  sourceLang: string;
  targetLang: string;
  input: string;
  output: string;
}
