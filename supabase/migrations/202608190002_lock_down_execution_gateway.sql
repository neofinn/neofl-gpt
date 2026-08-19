-- Execution gateway tables contain broker account identifiers, orders and PnL.
-- They are backend-only. The browser reads them through the authenticated
-- NeoFL gateway, never directly through Supabase Data API.

alter table public.gateway_accounts enable row level security;
alter table public.gateway_order_intents enable row level security;
alter table public.gateway_execution_reports enable row level security;

revoke all on table public.gateway_accounts from anon, authenticated;
revoke all on table public.gateway_order_intents from anon, authenticated;
revoke all on table public.gateway_execution_reports from anon, authenticated;

grant all on table public.gateway_accounts to service_role;
grant all on table public.gateway_order_intents to service_role;
grant all on table public.gateway_execution_reports to service_role;

-- No anon/authenticated policies are intentional. The Python gateway is the
-- only application path and uses the server-side Supabase service credential.
