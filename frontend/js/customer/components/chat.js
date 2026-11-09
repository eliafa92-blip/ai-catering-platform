import { fill, h, icon } from "../../lib/dom.js";
import { announce } from "../../lib/announce.js";
import { fmtMoney, fmtSignedMoney } from "../../lib/format.js";
import { suggestedPrompts } from "../mock-backend.js";
import { confetti } from "../../lib/motion.js";
import { mascotAvatar } from "./mascot.js";
import {
  approveProposalById, getState, proposalStatus, rejectProposal, sendChat, setChatOpen, subscribe,
} from "../store.js";

const STATUS_NOTE = {
  applying: ["badge-warning", "מחיל את השינוי..."],
  applied: ["badge-green", "השינוי הוחל בהזמנה"],
  rejected: ["", "השינוי נדחה"],
  expired: ["badge-warning", "ההזמנה השתנתה. בקשו מהעוזר הצעה חדשה."],
};

function proposalCard(p) {
  const status = proposalStatus(p);
  const delta = p.price_after - p.price_before;
  const note = STATUS_NOTE[status];
  return h("section", { class: `proposal is-${status}`, "aria-label": "שינוי מוצע בהזמנה" },
    h("h4", { class: "proposal-title", text: "שינוי מוצע" }),
    h("ul", { class: "proposal-rows" },
      p.diff.map((d) => h("li", { class: "proposal-row" },
        h("span", { class: "proposal-label", text: d.label }),
        h("span", { class: "proposal-change" },
          h("span", { class: "muted", text: d.current }),
          icon("caret-left"),
          h("strong", { text: d.proposed }),
        ),
      )),
    ),
    h("div", { class: "proposal-total" },
      h("span", { text: "סה״כ להזמנה" }),
      h("span", { class: "proposal-change" },
        h("span", { class: "muted", text: fmtMoney(p.price_before) }),
        icon("caret-left"),
        h("strong", { text: fmtMoney(p.price_after) }),
        // dir=ltr keeps the sign next to the number instead of being reordered by the RTL context.
        h("span", { class: `delta ${delta > 0 ? "up" : delta < 0 ? "down" : ""}`, dir: "ltr", text: `(${fmtSignedMoney(delta)})` }),
      ),
    ),
    status === "pending"
      ? h("div", { class: "proposal-actions" },
        h("button", { class: "btn btn-secondary", type: "button", "data-key": `rej-${p.id}`, onclick: () => rejectProposal(p.id) }, "דחייה"),
        h("button", { class: "btn btn-primary", type: "button", "data-key": `app-${p.id}`, onclick: () => approveProposalById(p.id) }, "אישור השינוי"),
      )
      : h("div", { class: "proposal-done" },
        // Celebrating only acknowledges a change the customer approved; it is never shown on a pending proposal.
        status === "applied" ? mascotAvatar("celebrating", { size: 32 }) : null,
        h("p", { class: `badge ${note[0]}` }, status === "applied" ? icon("check") : null, note[1])),
  );
}

// Mascot state per message: a message that carries a proposal is "suggesting"; any other answer
// (price, quantities, allergens) is "explaining". The state is chosen here from the message itself.
function bubble(m, isNew) {
  const fresh = isNew ? " is-new" : "";
  if (m.role !== "assistant") return h("li", { class: `msg msg-user${fresh}` }, h("div", { class: "msg-text", text: m.text }));
  return h("li", { class: `msg msg-assistant${fresh}` },
    mascotAvatar(m.proposals.length ? "suggesting" : "explaining", { size: 36 }),
    h("div", { class: "msg-main" },
      h("div", { class: "msg-text", text: m.text }),
      m.proposals.map(proposalCard)),
  );
}

export function mountChat(root) {
  const list = h("ol", { class: "chat-log", role: "log", "aria-live": "polite", "aria-label": "שיחה עם העוזר" });
  const input = h("textarea", { class: "input chat-input", rows: "1", id: "chat-input", placeholder: "כתבו שאלה על ההזמנה", "aria-label": "הודעה לעוזר" });
  const sendBtn = h("button", { class: "btn btn-primary btn-icon", type: "submit", "aria-label": "שליחה" }, icon("paper-plane-right"));
  const prompts = h("div", { class: "chip-row chat-prompts" });
  const closeBtn = h("button", { class: "btn btn-ghost btn-icon", type: "button", "aria-label": "סגירת העוזר", onclick: () => setChatOpen(false) }, icon("x"));

  const panel = h("aside", { class: "chat-panel", role: "dialog", "aria-modal": "true", "aria-labelledby": "chat-title", id: "chat-panel" },
    h("header", { class: "chat-head" },
      h("div", { class: "chat-id" },
        mascotAvatar("welcome", { size: 52 }),
        h("div", {},
          h("h2", { class: "chat-title", id: "chat-title" }, "העוזר החכם"),
          h("p", { class: "muted small", text: "ההצעות שלי מתבצעות רק אחרי שתאשרו אותן." }),
        ),
      ),
      closeBtn,
    ),
    list,
    prompts,
    h("form", { class: "chat-form", onsubmit: (e) => {
      e.preventDefault();
      const text = input.value;
      input.value = "";
      sendChat(text);
    } }, input, sendBtn),
  );

  input.addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      panel.querySelector("form").requestSubmit();
    }
  });
  // Escape closes; Tab/Shift+Tab is trapped inside the panel so a keyboard user can't tab into
  // the (inert, but belt-and-suspenders) background content behind it.
  panel.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { setChatOpen(false); return; }
    if (e.key !== "Tab") return;
    const focusables = [...panel.querySelectorAll('button, [href], input, textarea, select, [tabindex]:not([tabindex="-1"])')]
      .filter((el) => !el.disabled && !el.hidden);
    if (!focusables.length) return;
    const first = focusables[0];
    const last = focusables[focusables.length - 1];
    if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
    else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
  });

  // Marks every top-level sibling of this component's own root inert while the panel is open,
  // so background content (the menu/summary behind the chat) is unreachable by keyboard, mouse
  // or screen reader. The shared #announce live region is excluded so status announcements keep
  // working while the chat is open.
  function setBackgroundInert(inert) {
    for (const el of document.body.children) {
      if (el === root || el.id === "announce") continue;
      el.inert = inert;
    }
  }

  const fab = h("button", { class: "chat-fab btn btn-primary", type: "button", "aria-controls": "chat-panel", "aria-expanded": "false", onclick: () => setChatOpen(true) },
    mascotAvatar("welcome", { size: 36, cls: "on-dark" }), "שאלו את העוזר");
  const backdrop = h("div", { class: "chat-backdrop", onclick: () => setChatOpen(false) });

  root.append(backdrop, panel, fab);

  let last = {};
  function render(state) {
    const available = (state.step === "menu" || state.step === "summary") && state.order.status === "draft";
    const { open, busy, messages } = state.chat;
    root.hidden = !available;
    document.body.classList.toggle("chat-open", available && open);
    fab.hidden = open;
    fab.setAttribute("aria-expanded", String(open));
    panel.hidden = !open;
    backdrop.hidden = !open;
    setBackgroundInert(open);

    const sig = { messages, busy, version: state.order.version };
    if (open && (sig.messages !== last.messages || sig.busy !== last.busy || sig.version !== last.version)) {
      const focusKey = list.contains(document.activeElement) ? document.activeElement.dataset.key : null;
      fill(list, 
        messages.length ? null : h("li", { class: "msg msg-assistant" },
          mascotAvatar("welcome", { size: 36 }),
          h("div", { class: "msg-main" }, h("div", { class: "msg-text", text: "שלום! אני יכול להמליץ על מנות, לבדוק כמויות ולהסביר את המחיר. אפשר גם לשאול על אלרגנים." }))),
        // Only messages added since the last render animate in; the rest stay put.
        messages.map((m, i) => bubble(m, last.count !== undefined && i >= last.count)),
        busy ? h("li", { class: "msg msg-assistant is-new" },
          mascotAvatar("thinking", { size: 36, cls: "is-thinking" }),
          h("div", { class: "msg-main" }, h("div", { class: "msg-text typing", text: "העוזר מקליד" }))) : null,
      );
      if (focusKey) list.querySelector(`[data-key="${focusKey}"]`)?.focus();
      list.scrollTop = list.scrollHeight;
      // role=log announces new bubbles; applied proposals change the order silently, so announce them.
      const applied = messages.flatMap((m) => m.proposals).filter((p) => p.status === "applied").length;
      if (applied !== last.applied) {
        if (last.applied !== undefined) {
          announce("השינוי הוחל בהזמנה");
          // A small celebration, only for a change the customer just approved.
          confetti([...list.querySelectorAll(".proposal-done .mascot-avatar")].at(-1));
        }
        last.applied = applied;
      }
      Object.assign(last, sig, { count: messages.length });
    }
    fill(prompts, 
      messages.length === 0 && open
        ? suggestedPrompts().map((q) => h("button", { class: "chip", type: "button", onclick: () => sendChat(q) }, q))
        : null,
    );
    sendBtn.disabled = busy;
  }

  let wasOpen = false;
  subscribe((state) => {
    render(state);
    if (state.chat.open && !wasOpen) input.focus();
    if (!state.chat.open && wasOpen && !fab.hidden) fab.focus();
    wasOpen = state.chat.open;
  });
  render(getState());
}
