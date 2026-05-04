import "./style.css";
import { ACTIONS, TARGET_LANGUAGES, buildInstruction, languageDisplayName } from "./actions";
import { AVAILABLE_MODELS, loadSettings, saveSettings } from "./storage";
import { AUTH_REQUIRED, streamChat } from "./llm";
import { parseGrammarCheck, parseSentencePairs } from "./parsers";
import { wordDiff } from "./diff";
import { renderMarkdown } from "./markdown";
import { escapeHTML } from "./utils";
import { createCheckoutSession, type BillingPlan } from "./billing";
import {
  consumeOAuthCallbackIfPresent,
  getCurrentSession,
  onAuthChange,
  signInWith,
  signOut,
  type AuthProvider,
} from "./auth-session";
import {
  appendHistory,
  deleteHistoryEntry,
  listHistory,
  loadCloudSettings,
  saveCloudSettings,
} from "./cloud-storage";
import { cancelGoogleOneTap, googleOneTapConfigured, promptGoogleOneTap } from "./google-onetap";
import { supabaseConfigured } from "./supabase";
import type { ActionConfig, AppSettings, TranslationHistoryEntry } from "./types";

const APP_STORE_URL = "https://apps.apple.com/app/id6754217103";
const PROXY_PREFIX = __CLOUD_PROXY_PREFIX__;

const SOURCE_LANGUAGES: { code: string; name: string }[] = [
  { code: "auto", name: "Detect language" },
  ...TARGET_LANGUAGES,
];

const app = document.querySelector<HTMLDivElement>("#app")!;

let settings: AppSettings = loadSettings();
let currentAction: ActionConfig = ACTIONS[0];
let currentAbort: AbortController | null = null;
let sourceLanguage = "auto";
let currentUserEmail: string | null = null;

app.innerHTML = `
  <header class="topbar">
    <a class="brand" href="${APP_STORE_URL}" target="_blank" rel="noopener">
      <div class="logo">T</div>
      <div class="title">TLingo</div>
    </a>
    <div class="topbar-right">
      <button id="settings-btn" class="icon-btn" title="Settings" aria-label="Settings">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
             stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="3"></circle>
          <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51 1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1 1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
        </svg>
      </button>
      <div id="account-slot" class="account-slot"></div>
      <a class="cta-btn" href="${APP_STORE_URL}" target="_blank" rel="noopener">Try TLingo</a>
    </div>
  </header>

  <main class="page">
    <h1 class="hero">Translate with TLingo</h1>

    <div class="lang-bar">
      <select id="source-lang" class="lang-select" aria-label="Source language"></select>
      <button id="swap-btn" class="swap-btn" title="Swap languages" aria-label="Swap languages">
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
             stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <path d="M7 7h13M7 7l4-4M7 7l4 4"/>
          <path d="M17 17H4M17 17l-4 4M17 17l-4-4"/>
        </svg>
      </button>
      <select id="target-lang" class="lang-select" aria-label="Target language"></select>
    </div>

    <div class="io-grid">
      <section class="io-card input-card">
        <textarea id="input" placeholder="Type or paste text to translate" autocomplete="off" spellcheck="false"></textarea>
        <div class="io-footer">
          <span class="hint" id="char-count">0</span>
          <div class="io-actions">
            <button id="clear-btn" class="text-btn" title="Clear">Clear</button>
            <button id="run-btn" class="primary-btn">Translate</button>
          </div>
        </div>
      </section>

      <section class="io-card output-card" id="output-card">
        <div class="output-body" id="output">
          <div class="placeholder">Result will appear here.</div>
        </div>
        <div class="io-footer right">
          <button id="copy-btn" class="icon-action" title="Copy" aria-label="Copy result" hidden>
            <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor"
                 stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
              <rect x="9" y="9" width="11" height="11" rx="2"/>
              <path d="M5 15V5a2 2 0 0 1 2-2h10"/>
            </svg>
          </button>
        </div>
      </section>
    </div>

    <div class="action-grid" id="action-grid"></div>

    <section class="billing-panel" aria-labelledby="billing-title">
      <div class="billing-copy">
        <div class="eyebrow">Pro</div>
        <h2 id="billing-title">Unlock premium translation models</h2>
        <p>Use TLingo with higher-capability models for longer, harder translation work.</p>
      </div>
      <div class="billing-plans">
        <button class="plan-btn" data-plan="monthly">
          <span class="plan-name">Monthly</span>
          <span class="plan-price">$3</span>
          <span class="plan-cadence">per month</span>
        </button>
        <button class="plan-btn featured" data-plan="yearly">
          <span class="plan-name">Yearly</span>
          <span class="plan-price">$20</span>
          <span class="plan-cadence">per year</span>
        </button>
      </div>
      <p class="billing-status" id="billing-status" aria-live="polite"></p>
    </section>
  </main>

  <div class="modal" id="settings-modal" hidden>
    <div class="modal-backdrop" data-close></div>
    <div class="modal-card">
      <div class="modal-header">
        <div class="modal-title">Settings</div>
        <button class="icon-btn" data-close aria-label="Close">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
        </button>
      </div>
      <div class="modal-body">
        <label class="field">
          <span>Model</span>
          <select id="set-model" class="field-select"></select>
        </label>
        <p class="note">
          Requests are signed with the shared HMAC secret loaded from <code>.env</code>
          and routed to the same backend the iOS client uses.
        </p>
      </div>
      <div class="modal-footer">
        <button id="settings-cancel" class="text-btn" data-close>Cancel</button>
        <button id="settings-save" class="primary-btn">Save</button>
      </div>
    </div>
  </div>

  <div class="modal" id="signin-modal" hidden>
    <div class="modal-backdrop" data-close></div>
    <div class="modal-card">
      <div class="modal-header">
        <div class="modal-title">Sign in to TLingo</div>
        <button class="icon-btn" data-close aria-label="Close">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
        </button>
      </div>
      <div class="modal-body">
        <p class="signin-lede">Sign in to translate, sync settings across devices, and keep your history.</p>
        <button class="oauth-btn" data-provider="github">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
            <path d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.8 10.9.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.5-3.9-1.5-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.8 1.3 3.5 1 .1-.8.4-1.3.8-1.6-2.6-.3-5.3-1.3-5.3-5.7 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.2 1.2.9-.3 1.9-.4 2.9-.4s2 .1 2.9.4c2.2-1.5 3.2-1.2 3.2-1.2.6 1.6.2 2.8.1 3.1.7.8 1.2 1.8 1.2 3.1 0 4.4-2.7 5.4-5.3 5.7.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6 4.5-1.5 7.8-5.8 7.8-10.9C23.5 5.7 18.3.5 12 .5Z"/>
          </svg>
          <span>Continue with GitHub</span>
        </button>
        <button class="oauth-btn" data-provider="google">
          <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
            <path fill="#4285F4" d="M23.5 12.3c0-.8-.1-1.6-.2-2.3H12v4.5h6.5c-.3 1.5-1.1 2.7-2.4 3.6v3h3.9c2.3-2.1 3.5-5.2 3.5-8.8Z"/>
            <path fill="#34A853" d="M12 24c3.2 0 5.9-1.1 7.9-2.9l-3.9-3c-1.1.7-2.4 1.2-4 1.2-3.1 0-5.7-2.1-6.6-4.9H1.4v3.1C3.4 21.4 7.4 24 12 24Z"/>
            <path fill="#FBBC05" d="M5.4 14.4c-.2-.7-.4-1.4-.4-2.4s.1-1.7.4-2.4V6.5H1.4C.5 8.2 0 10 0 12s.5 3.8 1.4 5.5l4-3.1Z"/>
            <path fill="#EA4335" d="M12 4.8c1.8 0 3.3.6 4.6 1.8l3.4-3.4C17.9 1.2 15.2 0 12 0 7.4 0 3.4 2.6 1.4 6.5l4 3.1C6.3 6.9 8.9 4.8 12 4.8Z"/>
          </svg>
          <span>Continue with Google</span>
        </button>
        <p class="note signin-note" id="signin-note" hidden></p>
      </div>
    </div>
  </div>

  <div class="modal" id="history-modal" hidden>
    <div class="modal-backdrop" data-close></div>
    <div class="modal-card history-card">
      <div class="modal-header">
        <div class="modal-title">History</div>
        <button class="icon-btn" data-close aria-label="Close">
          <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor"
               stroke-width="1.8" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
        </button>
      </div>
      <div class="modal-body history-body" id="history-body">
        <div class="placeholder">Loading…</div>
      </div>
    </div>
  </div>

  <div class="account-popover" id="account-popover" hidden>
    <div class="account-email" id="account-email"></div>
    <button class="popover-btn" id="open-history-btn">History</button>
    <button class="popover-btn" id="signout-btn">Sign out</button>
  </div>
`;

const inputEl = document.getElementById("input") as HTMLTextAreaElement;
const charCountEl = document.getElementById("char-count")!;
const runBtn = document.getElementById("run-btn") as HTMLButtonElement;
const clearBtn = document.getElementById("clear-btn") as HTMLButtonElement;
const outputEl = document.getElementById("output")!;
const copyBtn = document.getElementById("copy-btn") as HTMLButtonElement;
const sourceLangEl = document.getElementById("source-lang") as HTMLSelectElement;
const targetLangEl = document.getElementById("target-lang") as HTMLSelectElement;
const swapBtn = document.getElementById("swap-btn") as HTMLButtonElement;
const actionGridEl = document.getElementById("action-grid")!;
const settingsBtn = document.getElementById("settings-btn") as HTMLButtonElement;
const modal = document.getElementById("settings-modal")!;
const setModel = document.getElementById("set-model") as HTMLSelectElement;
const settingsSave = document.getElementById("settings-save") as HTMLButtonElement;
const accountSlot = document.getElementById("account-slot")!;
const accountPopover = document.getElementById("account-popover") as HTMLDivElement;
const accountEmailEl = document.getElementById("account-email")!;
const openHistoryBtn = document.getElementById("open-history-btn") as HTMLButtonElement;
const signOutBtn = document.getElementById("signout-btn") as HTMLButtonElement;
const signinModal = document.getElementById("signin-modal")!;
const signinNote = document.getElementById("signin-note")!;
const historyModal = document.getElementById("history-modal")!;
const historyBody = document.getElementById("history-body")!;
const billingStatus = document.getElementById("billing-status")!;
const planButtons = Array.from(document.querySelectorAll<HTMLButtonElement>(".plan-btn"));

AVAILABLE_MODELS.forEach((m) => {
  const opt = document.createElement("option");
  opt.value = m.id;
  opt.textContent = m.name;
  setModel.appendChild(opt);
});

SOURCE_LANGUAGES.forEach((l) => {
  const opt = document.createElement("option");
  opt.value = l.code;
  opt.textContent = l.name;
  sourceLangEl.appendChild(opt);
});
TARGET_LANGUAGES.forEach((l) => {
  const opt = document.createElement("option");
  opt.value = l.code;
  opt.textContent = l.name;
  targetLangEl.appendChild(opt);
});
sourceLangEl.value = sourceLanguage;
targetLangEl.value = settings.targetLanguage;

sourceLangEl.addEventListener("change", () => {
  sourceLanguage = sourceLangEl.value;
});
targetLangEl.addEventListener("change", () => {
  settings.targetLanguage = targetLangEl.value;
  persistSettings();
});

swapBtn.addEventListener("click", () => {
  if (sourceLanguage === "auto") return;
  const prev = sourceLanguage;
  sourceLanguage = settings.targetLanguage;
  settings.targetLanguage = prev;
  sourceLangEl.value = sourceLanguage;
  targetLangEl.value = settings.targetLanguage;
  persistSettings();
});

ACTIONS.forEach((a, i) => {
  const card = document.createElement("button");
  card.className = "action-card" + (i === 0 ? " active" : "");
  card.dataset.id = a.id;
  const name = document.createElement("div");
  name.className = "action-name";
  name.textContent = a.name;
  const desc = document.createElement("div");
  desc.className = "action-desc";
  desc.textContent = a.description;
  card.append(name, desc);
  card.addEventListener("click", () => selectAction(a));
  actionGridEl.appendChild(card);
});

inputEl.addEventListener("input", () => {
  charCountEl.textContent = `${inputEl.value.length}`;
});

inputEl.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
    e.preventDefault();
    if (currentAbort) stop();
    else run();
  }
});

clearBtn.addEventListener("click", () => {
  inputEl.value = "";
  charCountEl.textContent = "0";
  resetOutput();
  inputEl.focus();
});

runBtn.onclick = () => {
  if (currentAbort) stop();
  else run();
};

copyBtn.addEventListener("click", async () => {
  const text = outputEl.dataset.raw ?? outputEl.textContent ?? "";
  try {
    await navigator.clipboard.writeText(text);
    copyBtn.classList.add("copied");
    setTimeout(() => copyBtn.classList.remove("copied"), 1200);
  } catch {
    // ignore
  }
});

settingsBtn.addEventListener("click", () => openSettings());
modal.addEventListener("click", (e) => {
  const t = e.target as HTMLElement;
  if (t.dataset.close !== undefined) closeSettings();
});
settingsSave.addEventListener("click", () => {
  settings = { ...settings, model: setModel.value };
  persistSettings();
  closeSettings();
});

function openSettings() {
  setModel.value = settings.model;
  modal.hidden = false;
}

function closeSettings() {
  modal.hidden = true;
}

function selectAction(a: ActionConfig) {
  if (currentAction.id === a.id) return;
  if (currentAbort) {
    currentAbort.abort();
    currentAbort = null;
    setRunning(false);
  }
  currentAction = a;
  document.querySelectorAll(".action-card").forEach((el) => {
    el.classList.toggle("active", (el as HTMLElement).dataset.id === a.id);
  });
  resetOutput();
}

function resetOutput() {
  outputEl.innerHTML = `<div class="placeholder">Result will appear here.</div>`;
  outputEl.dataset.raw = "";
  copyBtn.hidden = true;
}

function setRunning(running: boolean) {
  if (running) {
    runBtn.textContent = "Stop";
    runBtn.classList.add("danger");
  } else {
    runBtn.textContent = currentAction.id === "translate" ? "Translate" : "Run";
    runBtn.classList.remove("danger");
  }
}

function stop() {
  currentAbort?.abort();
  currentAbort = null;
  setRunning(false);
}

async function run() {
  const text = inputEl.value.trim();
  if (!text) {
    inputEl.focus();
    return;
  }
  resetOutput();
  const instruction = buildInstruction(currentAction.prompt, settings.targetLanguage);

  const controller = new AbortController();
  currentAbort = controller;
  setRunning(true);

  let acc = "";
  const isStreamingText =
    currentAction.outputType === "translate" ||
    currentAction.outputType === "diff" ||
    currentAction.outputType === "plain";

  if (isStreamingText) {
    outputEl.innerHTML = `<div class="streaming"></div>`;
  } else {
    outputEl.innerHTML = `
      <div class="subhead">Streaming…</div>
      <pre class="streaming raw"></pre>
    `;
  }
  const streamEl = outputEl.querySelector(".streaming") as HTMLElement;

  await streamChat(
    settings,
    [
      {
        role: "system",
        content:
          "You are a precise multilingual assistant. The user gives you an INSTRUCTION followed by INPUT text wrapped in <input>…</input> tags. Apply the instruction to the input text only — never translate or modify the instruction itself. Follow output format exactly.",
      },
      {
        role: "user",
        content: `${instruction}\n\n<input>\n${text}\n</input>`,
      },
    ],
    {
      signal: controller.signal,
      onDelta: (chunk) => {
        if (currentAbort !== controller) return;
        acc += chunk;
        if (currentAction.outputType === "plain") {
          streamEl.innerHTML = renderMarkdown(acc);
        } else {
          streamEl.textContent = acc;
        }
      },
      onDone: (full) => {
        if (currentAbort !== controller) return;
        currentAbort = null;
        setRunning(false);
        try {
          renderFinal(text, full);
        } catch (e) {
          showError("Render error: " + (e instanceof Error ? e.message : String(e)));
        }
        appendHistory({
          actionId: currentAction.id,
          sourceLang: sourceLanguage,
          targetLang: settings.targetLanguage,
          input: text,
          output: full,
        }).catch(() => {});
      },
      onError: (err) => {
        const isStale = currentAbort !== controller;
        if (!isStale) {
          currentAbort = null;
          setRunning(false);
        }
        if (isStale || err.name === "AbortError" || /aborted/i.test(err.message)) return;
        if (err.message === AUTH_REQUIRED) {
          resetOutput();
          openSignin("Sign in to run translations.");
          return;
        }
        showError(err.message);
      },
    },
  );
}

function renderDiffSegments(oldText: string, newText: string): string {
  return wordDiff(oldText, newText)
    .map((s) => {
      const t = escapeHTML(s.text);
      if (s.op === "equal") return `<span>${t}</span>`;
      if (s.op === "insert") return `<span class="ins">${t}</span>`;
      return `<span class="del">${t}</span>`;
    })
    .join("");
}

function renderFinal(originalInput: string, full: string) {
  outputEl.dataset.raw = full;
  copyBtn.hidden = false;

  switch (currentAction.outputType) {
    case "translate":
      outputEl.innerHTML = `<div class="text-block">${escapeHTML(full)}</div>`;
      break;
    case "plain":
      outputEl.innerHTML = `<div class="md">${renderMarkdown(full)}</div>`;
      break;
    case "diff": {
      outputEl.innerHTML = `
        <div class="diff-block">${renderDiffSegments(originalInput, full)}</div>
        <div class="subhead">Polished</div>
        <div class="text-block">${escapeHTML(full)}</div>
      `;
      break;
    }
    case "sentencePairs": {
      const pairs = parseSentencePairs(full);
      if (pairs.length === 0) {
        outputEl.innerHTML = `<div class="text-block">${escapeHTML(full)}</div>`;
        return;
      }
      outputEl.innerHTML = `<div class="pairs">${pairs
        .map(
          (p) => `
        <div class="pair">
          <div class="pair-original">${escapeHTML(p.original)}</div>
          <div class="pair-translation">${escapeHTML(p.translation)}</div>
        </div>`,
        )
        .join("")}</div>`;
      outputEl.dataset.raw = pairs.map((p) => `${p.original}\n${p.translation}`).join("\n\n");
      break;
    }
    case "grammarCheck": {
      const result = parseGrammarCheck(full);
      if (!result) {
        outputEl.innerHTML = `<div class="text-block">${escapeHTML(full)}</div>`;
        return;
      }
      outputEl.innerHTML = `
        <div class="subhead">Polished</div>
        <div class="diff-block">${renderDiffSegments(originalInput, result.polished)}</div>
        <div class="subhead">Explanation</div>
        <div class="md">${renderMarkdown(result.explanation)}</div>
        <div class="subhead">Translation</div>
        <div class="text-block">${escapeHTML(result.translation)}</div>
      `;
      outputEl.dataset.raw = `${result.polished}\n\n${result.explanation}\n\n${result.translation}`;
      break;
    }
  }
}

function showError(msg: string) {
  outputEl.innerHTML = `<div class="error">${escapeHTML(msg)}</div>`;
  copyBtn.hidden = true;
}

function persistSettings() {
  saveSettings(settings);
  if (currentUserEmail) saveCloudSettings(settings).catch(() => {});
}

function openSignin(note?: string) {
  cancelGoogleOneTap();
  if (!supabaseConfigured) {
    signinNote.textContent =
      "Supabase is not configured. Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY in .env.";
    signinNote.hidden = false;
  } else if (note) {
    signinNote.textContent = note;
    signinNote.hidden = false;
  } else {
    signinNote.hidden = true;
    signinNote.textContent = "";
  }
  signinModal.hidden = false;
}

function closeSignin() {
  signinModal.hidden = true;
}

function openHistory() {
  historyModal.hidden = false;
  renderHistory();
}

function closeHistory() {
  historyModal.hidden = true;
}

signinModal.addEventListener("click", (e) => {
  const t = e.target as HTMLElement;
  if (t.dataset.close !== undefined) closeSignin();
});
historyModal.addEventListener("click", (e) => {
  const t = e.target as HTMLElement;
  if (t.dataset.close !== undefined) closeHistory();
  const del = t.closest("[data-history-delete]") as HTMLElement | null;
  if (del) {
    const id = del.dataset.historyDelete!;
    deleteHistoryEntry(id)
      .then(renderHistory)
      .catch(() => {});
  }
});

signinModal.querySelectorAll<HTMLButtonElement>(".oauth-btn").forEach((btn) => {
  btn.addEventListener("click", async () => {
    const provider = btn.dataset.provider as AuthProvider | undefined;
    if (!provider) return;
    btn.disabled = true;
    try {
      await signInWith(provider);
    } catch (e) {
      signinNote.textContent = e instanceof Error ? e.message : String(e);
      signinNote.hidden = false;
      btn.disabled = false;
    }
  });
});

accountSlot.addEventListener("click", (e) => {
  e.stopPropagation();
  if (!currentUserEmail) {
    openSignin();
    return;
  }
  accountPopover.hidden = !accountPopover.hidden;
  if (!accountPopover.hidden) positionPopover();
});

document.addEventListener("click", (e) => {
  if (accountPopover.hidden) return;
  const t = e.target as Node;
  if (!accountPopover.contains(t) && !accountSlot.contains(t)) {
    accountPopover.hidden = true;
  }
});

function positionPopover() {
  const r = accountSlot.getBoundingClientRect();
  accountPopover.style.top = `${r.bottom + 8}px`;
  accountPopover.style.right = `${window.innerWidth - r.right}px`;
}

openHistoryBtn.addEventListener("click", () => {
  accountPopover.hidden = true;
  openHistory();
});

signOutBtn.addEventListener("click", async () => {
  accountPopover.hidden = true;
  await signOut();
});

planButtons.forEach((button) => {
  button.addEventListener("click", () => {
    const plan = button.dataset.plan as BillingPlan | undefined;
    if (!plan) return;
    startCheckout(plan, button).catch((error) => {
      billingStatus.textContent = error instanceof Error ? error.message : String(error);
      planButtons.forEach((btn) => (btn.disabled = false));
    });
  });
});

async function startCheckout(plan: BillingPlan, sourceButton: HTMLButtonElement) {
  billingStatus.textContent = "Opening checkout...";
  planButtons.forEach((btn) => (btn.disabled = true));
  sourceButton.classList.add("loading");

  try {
    const checkout = await createCheckoutSession(PROXY_PREFIX, plan, currentUserEmail);
    window.location.assign(checkout.url);
  } finally {
    sourceButton.classList.remove("loading");
  }
}

function updateAccountUI() {
  accountSlot.innerHTML = "";
  if (currentUserEmail) {
    const initial = currentUserEmail.trim().charAt(0).toUpperCase() || "?";
    const avatar = document.createElement("button");
    avatar.className = "avatar-btn";
    avatar.title = currentUserEmail;
    avatar.setAttribute("aria-label", `Account: ${currentUserEmail}`);
    avatar.textContent = initial;
    accountSlot.appendChild(avatar);
    accountEmailEl.textContent = currentUserEmail;
  } else {
    const signin = document.createElement("button");
    signin.className = "text-btn signin-btn";
    signin.textContent = "Sign in";
    accountSlot.appendChild(signin);
    accountPopover.hidden = true;
  }
}

function actionName(id: string): string {
  return ACTIONS.find((a) => a.id === id)?.name ?? id;
}

async function renderHistory() {
  if (!currentUserEmail) {
    historyBody.innerHTML = `<div class="placeholder">Sign in to see history.</div>`;
    return;
  }
  historyBody.innerHTML = `<div class="placeholder">Loading…</div>`;
  let entries: TranslationHistoryEntry[] = [];
  try {
    entries = await listHistory(50);
  } catch {
    historyBody.innerHTML = `<div class="error">Failed to load history.</div>`;
    return;
  }
  if (entries.length === 0) {
    historyBody.innerHTML = `<div class="placeholder">No translations yet.</div>`;
    return;
  }
  historyBody.innerHTML = entries
    .map((e) => {
      const when = new Date(e.createdAt).toLocaleString();
      const langs = `${languageDisplayName(e.sourceLang)} → ${languageDisplayName(e.targetLang)}`;
      return `
        <div class="history-item">
          <div class="history-meta">
            <span class="history-action">${escapeHTML(actionName(e.actionId))}</span>
            <span class="history-langs">${escapeHTML(langs)}</span>
            <span class="history-time">${escapeHTML(when)}</span>
            <button class="text-btn history-del" data-history-delete="${escapeHTML(e.id)}">Delete</button>
          </div>
          <div class="history-input">${escapeHTML(e.input)}</div>
          <div class="history-output">${escapeHTML(e.output)}</div>
        </div>`;
    })
    .join("");
}

async function bootstrapAuth() {
  if (!supabaseConfigured) {
    updateAccountUI();
    return;
  }
  await consumeOAuthCallbackIfPresent();
  onAuthChange(async (user) => {
    const wasSignedIn = currentUserEmail !== null;
    currentUserEmail = user?.email ?? null;
    updateAccountUI();
    if (user) {
      cancelGoogleOneTap();
    }
    if (user && !wasSignedIn) {
      closeSignin();
      const cloud = await loadCloudSettings();
      if (cloud) {
        settings = { ...settings, ...cloud };
        saveSettings(settings);
        if (cloud.targetLanguage) targetLangEl.value = cloud.targetLanguage;
      } else {
        saveCloudSettings(settings).catch(() => {});
      }
    }
  });
  const session = await getCurrentSession();
  if (!session && googleOneTapConfigured) {
    promptGoogleOneTap().catch(() => {});
  }
}

updateAccountUI();
bootstrapAuth().catch(() => {});
