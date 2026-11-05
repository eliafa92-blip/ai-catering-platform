// Supabase client for the browser: auth, data (through RLS) and Realtime.
// Uses only the publishable key from /api/public-config; the secret key stays on the server.
import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.118.0/+esm";

let clientPromise;

export function getClient() {
  clientPromise ??= fetch("/api/public-config")
    .then((r) => r.json())
    .then(({ supabaseUrl, supabasePublishableKey }) => {
      if (!supabaseUrl || !supabasePublishableKey) {
        throw new Error("Supabase is not configured. Set SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY in .env.");
      }
      return createClient(supabaseUrl, supabasePublishableKey);
    });
  return clientPromise;
}

// The owner role lives in app_metadata, which users cannot edit.
export const isOwner = (user) => user?.app_metadata?.role === "owner";

export const homeFor = (user) => (isOwner(user) ? "/admin/" : "/customer/");

/** Returns the signed-in user, or sends the visitor to the login page. */
export async function requireUser({ owner = false } = {}) {
  const supabase = await getClient();
  const { data } = await supabase.auth.getUser();
  const user = data?.user;
  if (!user) {
    location.replace(`/login/?next=${encodeURIComponent(location.pathname)}`);
    return new Promise(() => {}); // stop the page while redirecting
  }
  if (owner && !isOwner(user)) {
    location.replace("/customer/");
    return new Promise(() => {});
  }
  return { supabase, user };
}

export async function signOut() {
  const supabase = await getClient();
  await supabase.auth.signOut();
  location.replace("/login/");
}

export const STATUS_LABELS = {
  draft: "Draft",
  pending_approval: "Awaiting business approval",
  approved: "Approved",
  rejected: "Rejected",
};

export const money = (value) =>
  value == null ? "—" : new Intl.NumberFormat("he-IL", { style: "currency", currency: "ILS" }).format(value);
