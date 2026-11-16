-- Realtime for leads, so /admin/leads/ sees new and changed leads live.
-- RLS still applies: only the owner's session receives anything here in practice,
-- since customers have no SELECT policy covering contact_form leads.

alter publication supabase_realtime add table public.leads;

-- Send the previous row on UPDATE, so the admin UI can see e.g. the old status.
alter table public.leads replica identity full;
