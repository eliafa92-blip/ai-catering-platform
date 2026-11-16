import { h, icon } from "../../lib/dom.js";

/** Number field with +/- buttons. Returns { el, input, set(value), setErrorDescribedBy(id|null) }.
    `name` labels the +/- buttons per field (e.g. "מבוגרים") so several counters on one page
    don't all announce as generic "הפחתה"/"הוספה" to a screen reader. */
export function counter({ id, value, min = 0, max = 500, onChange, describedBy, name, required = false }) {
  const input = h("input", {
    id, class: "input counter-input", type: "number", inputmode: "numeric",
    min: String(min), max: String(max), step: "1", value: String(value),
    "aria-describedby": describedBy,
    "aria-required": required ? "true" : null,
  });
  const clamp = (n) => Math.min(max, Math.max(min, Number.isFinite(n) ? n : min));
  const commit = (n) => {
    const next = clamp(n);
    input.value = String(next);
    onChange(next);
  };
  input.addEventListener("change", () => commit(Math.trunc(Number(input.value))));
  const step = (delta) => commit((Number(input.value) || 0) + delta);
  const el = h("div", { class: "counter" },
    h("button", { type: "button", class: "btn btn-secondary btn-icon", "aria-label": `הפחתת כמות: ${name}`, onclick: () => step(-1) }, icon("minus")),
    input,
    h("button", { type: "button", class: "btn btn-secondary btn-icon", "aria-label": `הוספת כמות: ${name}`, onclick: () => step(1) }, icon("plus")),
  );
  return {
    el, input,
    set: (v) => (input.value = String(v)),
    // Toggles an error id in/out of aria-describedby, keeping the base hint id in place.
    setErrorDescribedBy: (id) => {
      const base = describedBy ? describedBy.split(" ") : [];
      input.setAttribute("aria-describedby", id ? [...base, id].join(" ") : base.join(" "));
    },
  };
}
