class EnableRowLevelSecurityOnUsers < ActiveRecord::Migration[8.0]
  # This is the DB-enforced layer on top of TenantScoped's application-level
  # scoping. TenantScoped protects you from a missed `where(tenant_id:)` in
  # Ruby; this protects you from raw SQL, a console session, a model that
  # forgot to include TenantScoped, or a BI tool connecting straight to
  # Postgres — none of which go through ActiveRecord's default_scope at all.
  #
  # IMPORTANT — this only actually protects you if the role your Rails app
  # connects as does NOT own these tables and does NOT have BYPASSRLS.
  # Table owners and superusers bypass RLS by default regardless of policies
  # or FORCE ROW LEVEL SECURITY. In most setups the migration-running role
  # and the app's runtime role are the same, which defeats this entirely —
  # you need a separate, restricted app role. See README for the exact
  # `GRANT`/`ALTER ROLE` setup.
  #
  # Repeat this same pattern (ENABLE/FORCE/CREATE POLICY) for every other
  # tenant-owned table you add — it is NOT inherited from the `users` table.
  def up
    execute <<~SQL
      ALTER TABLE users ENABLE ROW LEVEL SECURITY;
      ALTER TABLE users FORCE ROW LEVEL SECURITY;

      CREATE POLICY tenant_isolation ON users
        USING (
          tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint
          OR current_setting('app.bypass_rls', true) = 'on'
        );
    SQL
  end

  def down
    execute <<~SQL
      DROP POLICY IF EXISTS tenant_isolation ON users;
      ALTER TABLE users NO FORCE ROW LEVEL SECURITY;
      ALTER TABLE users DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
