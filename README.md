# Multi-tenant SaaS boilerplate (Rails 8, shared DB)

> This is the tenancy/auth/webhook layer only — the parts that are easy to
> get subtly wrong. Generate a fresh app and drop these files in:
> `rails new myapp --database=postgresql --css=tailwind`, then copy
> `app/`, `db/migrate/`, `config/routes.rb`, and the `Gemfile` lines over.

## What's here
- **Tenancy**: shared database, `tenant_id` column on every tenant-owned
  table, enforced at **two** layers:
  1. Application-level: `TenantScoped` concern (`app/models/concerns/tenant_scoped.rb`)
     — a `default_scope` that filters every read to `Current.tenant`, and
     raises if a scoped model is queried with no tenant set.
  2. Database-level: Postgres Row-Level Security. `db/migrate/*_enable_row_level_security_on_users.rb`
     enables and **forces** RLS on `users`, with a policy that reads a
     session variable (`app.current_tenant_id`) set on every request/job.
     This is the layer that still protects you if application-level
     scoping is bypassed somehow — raw SQL, a console session, a model
     that forgot to include `TenantScoped`, a BI tool connecting directly
     to Postgres. Layer 1 fails loud (raises) so mistakes get caught in
     dev; layer 2 fails closed (returns zero rows) as the last resort in
     production even if layer 1 was somehow skipped.
- **Auth**: Rails 8's native `has_secure_password` session pattern (what
  `bin/rails generate authentication` scaffolds), adapted so a `User`
  always belongs to a `Tenant` and sessions can't be resumed cross-tenant.
- **Tenant-aware background jobs**: `ApplicationJob` (`app/jobs/application_job.rb`)
  captures `Current.tenant` at enqueue time into the job's serialized
  payload (works with Sidekiq, Solid Queue, or any ActiveJob adapter —
  see the file for why this uses `#serialize`/`#deserialize` rather than
  prepending `tenant_id` onto `arguments`), and restores both `Current.tenant`
  and the RLS session variable before `perform` runs. See `ExampleTenantReportJob`.
- **Billing**: `Webhooks::LemonSqueezyController` — signature verification
  (HMAC-SHA256) + idempotent event recording via `WebhookEvent`. Event
  handling itself (`process_event`) is a stub with a `TODO` — there's no
  subscription/plan model yet, so wire that in when you add billing.

## Setting up RLS for real — the part that's easy to get wrong
`FORCE ROW LEVEL SECURITY` does **not** apply to the table owner or to
superusers — Postgres exempts them regardless of any policy. If your
Rails app connects using the same role that ran the migrations (the
default in most setups), RLS is silently a no-op and you'd have no idea.
You need a separate, restricted role for the app to connect as at runtime:

```sql
CREATE ROLE app_runtime LOGIN PASSWORD '...' NOSUPERUSER NOBYPASSRLS;
GRANT CONNECT ON DATABASE myapp_production TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_runtime;
```
Then point `config/database.yml`'s production credentials at `app_runtime`,
while migrations continue to run as the owning role. Confirm it's actually
enforced before trusting it:
```sql
SET ROLE app_runtime;
SET app.current_tenant_id = '999999';  -- a tenant that doesn't exist
SELECT count(*) FROM users;             -- must be 0, not "all users"
```

## Why shared-DB + tenant_id (vs. Apartment / DB-per-tenant)
You picked this, and it's the right default for most SaaS: cheapest to
run and back up, one migration path, works fine on a single Postgres
instance well past your first few thousand tenants. The risk is a missed
`where(tenant_id: ...)` leaking data across tenants. This boilerplate
addresses that with `default_scope` in `TenantScoped`, which:
- filters every read to `Current.tenant` automatically,
- **raises** (`TenantScoped::MissingTenantError`) if a scoped model is
  queried with no `Current.tenant` set, instead of silently returning
  all rows — so background jobs/console sessions fail loud, not leak quiet,
- requires the explicit `Model.unscoped_for_system! { ... }` escape hatch
  for legitimate cross-tenant access (admin tools, fan-out jobs), which is
  easy to grep for in an audit.

If you outgrow this — heavy per-tenant customization, hard compliance
requirements for data isolation, or tenants large enough that noisy-neighbor
query load becomes a real problem — schema-per-tenant (Apartment gem) or
DB-per-tenant are the next steps, in that order.

## Quick start (Docker, no local Ruby/Postgres needed)
```bash
cp .env.example .env   # fill in SECRET_KEY_BASE at minimum — bin/rails secret generates one
docker compose up --build
```
Then visit `http://acme.localhost:3000` (any subdomain works — tenants are
created via the registration flow, there's no allowlist). This builds and
runs the same production `Dockerfile` Kamal deploys, against a local
Postgres container — see `docker-compose.yml`.

## Setup (native)
```bash
bundle install
bin/rails db:create db:migrate db:seed
```

Rails resolves subdomains using `tld_length` (default `1`), which assumes a
domain like `example.com`. Plain `acme.localhost` only has one dot, so it
gets treated as *no* subdomain and every tenant page will 404. Two ways
around that in development:

**Easiest — use `lvh.me`**, which resolves to `127.0.0.1` and has enough
domain parts for the default `tld_length` to work with zero config:
```
http://acme.lvh.me:3000
```

**Or**, to keep using `*.localhost`, add to `config/environments/development.rb`:
```ruby
config.action_dispatch.tld_length = 0
```
and add `127.0.0.1 acme.localhost` to `/etc/hosts`.

Then:
```bash
bin/rails server
```
- `http://localhost:3000` → marketing site (no tenant)
- `http://acme.lvh.me:3000` → tenant app (seeded: `owner@acme.test` / `password123`)

## LemonSqueezy webhook
1. Add your signing secret: `bin/rails credentials:edit` →
   ```yaml
   lemon_squeezy:
     webhook_secret: whsec_...
   ```
2. Point LemonSqueezy's webhook URL at `POST /webhooks/lemon_squeezy`
   (this route is deliberately **outside** the subdomain constraints —
   it's not tenant-scoped, since the tenant has to be resolved from the
   payload, not from a subdomain).
3. Fill in `Webhooks::LemonSqueezyController#process_event` once you add
   a `Subscription`/`Plan` model. Use `event.payload.dig("meta", "custom_data", "tenant_id")`
   to resolve the tenant — set `custom_data` when creating the LemonSqueezy
   checkout URL so it round-trips back to you on every webhook.

## Deploying (Kamal)
`config/deploy.yml` is a starting point, not a finished deploy — every
`TODO` in it needs a real value (server IP, registry namespace, domain)
before `bin/kamal deploy` will work. Two things worth reading in the file
itself before you rely on it:
- **Wildcard subdomain SSL is unverified.** This app resolves tenants from
  `request.subdomain`, so it needs certs/routing for `*.yourdomain.com`,
  not just one hostname — I could not confirm locally whether `kamal-proxy`
  handles that out of the box. Test it against a real deploy first.
- **The RLS `app_runtime` role setup above still applies** — whichever host
  ends up running the `db` accessory, the app must connect as that
  restricted role, or RLS silently protects nothing.

Secrets (`RAILS_MASTER_KEY`, `SECRET_KEY_BASE`, DB password, registry
password) are read from your shell environment via `.kamal/secrets` — see
that file's comments. Nothing in `config/deploy.yml` or `.kamal/secrets` is
a literal secret, so both are safe to commit as-is.

## Not included (next steps)
- Invitations / multi-user-per-tenant admin UI (role field exists, no UI yet)
- Rate limiting beyond the login endpoint
- RLS policies on tables you add beyond `users` — copy the pattern in
  `db/migrate/*_enable_row_level_security_on_users.rb` for each new
  tenant-owned table; it is not inherited automatically
- A subscription/plan model — `Webhooks::LemonSqueezyController#process_event`
  is still a stub (see the LemonSqueezy section above)
  `spec/support/current_attributes.rb` already resets `Current` after
  every example, so `Current.tenant` set in one spec won't leak into
  the next one (this doesn't happen automatically outside real requests).
