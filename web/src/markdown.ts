import { escapeHTML } from "./utils";

function inline(s: string): string {
  let out = escapeHTML(s);
  out = out.replace(/`([^`]+)`/g, "<code>$1</code>");
  out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  out = out.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");
  return out;
}

export function renderMarkdown(src: string): string {
  const lines = src.split(/\r?\n/);
  const html: string[] = [];
  let inList = false;
  const flushList = () => {
    if (inList) {
      html.push("</ul>");
      inList = false;
    }
  };

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) {
      flushList();
      continue;
    }
    const h2 = line.match(/^##\s+(.*)$/);
    const h3 = line.match(/^###\s+(.*)$/);
    const li = line.match(/^[-*]\s+(.*)$/);
    if (h2) {
      flushList();
      html.push(`<h2>${inline(h2[1])}</h2>`);
    } else if (h3) {
      flushList();
      html.push(`<h3>${inline(h3[1])}</h3>`);
    } else if (li) {
      if (!inList) {
        html.push("<ul>");
        inList = true;
      }
      html.push(`<li>${inline(li[1])}</li>`);
    } else {
      flushList();
      html.push(`<p>${inline(line)}</p>`);
    }
  }
  flushList();
  return html.join("");
}
