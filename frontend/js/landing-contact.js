// "Leave your details" lead-capture form on the landing page. Anonymous, no account needed:
// inserted directly through Supabase with the anon/publishable key, same pattern as every other
// page in this app. RLS (20261116102123_leads_rls.sql) permits exactly this insert and nothing else.
import { getClient } from "./supabase.js";
import { EVENT_TYPES } from "./customer/mock-backend.js";
import { announce } from "./lib/announce.js";

const form = document.getElementById("contact-form");
if (form) {
  const typeSelect = document.getElementById("c-type");
  EVENT_TYPES.forEach((t) => typeSelect.add(new Option(t, t)));

  const nameInput = document.getElementById("c-name");
  const phoneInput = document.getElementById("c-phone");
  const nameError = document.getElementById("c-name-error");
  const phoneError = document.getElementById("c-phone-error");
  const submitBtn = form.querySelector("button[type=submit]");

  function setFieldError(input, errorEl, message) {
    input.setAttribute("aria-invalid", message ? "true" : "false");
    errorEl.textContent = message || "";
    errorEl.hidden = !message;
  }

  function validate() {
    let ok = true;
    if (!nameInput.value.trim()) {
      setFieldError(nameInput, nameError, "נא להזין שם.");
      ok = false;
    } else setFieldError(nameInput, nameError, "");
    if (!phoneInput.value.trim()) {
      setFieldError(phoneInput, phoneError, "נא להזין מספר טלפון.");
      ok = false;
    } else setFieldError(phoneInput, phoneError, "");
    return ok;
  }

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!validate()) {
      form.querySelector('[aria-invalid="true"]')?.focus();
      return;
    }
    submitBtn.disabled = true;
    submitBtn.textContent = "שולח…";
    try {
      const supabase = await getClient();
      const { error } = await supabase.from("leads").insert({
        source: "contact_form",
        status: "new",
        full_name: nameInput.value.trim(),
        phone: phoneInput.value.trim(),
        event_date: document.getElementById("c-date").value || null,
        event_type: typeSelect.value || null,
        referral_source: document.getElementById("c-referral").value || null,
        note: document.getElementById("c-note").value.trim() || null,
      });
      if (error) throw error;
      form.hidden = true;
      document.getElementById("contact-done").hidden = false;
      announce("הפרטים נשלחו בהצלחה. נחזור אליכם בהקדם.");
    } catch (error) {
      announce(`השליחה נכשלה: ${error.message}. אפשר לנסות שוב.`);
      submitBtn.disabled = false;
      submitBtn.textContent = "שליחה";
    }
  });
}
