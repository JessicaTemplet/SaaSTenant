# Sets BOTH halves of "tenant context" together: Current.tenant (what
# TenantScoped's app-level default_scope checks) and a Postgres
# session-level variable (a "GUC") that RLS policies read via
# current_setting('app.current_tenant_id', true) — the database-level
# check that holds even if a query somehow bypasses TenantScoped.
#
# These are two independent mechanisms, and setting only one of them is
# an easy, quiet mistake to make — a query would just raise
# TenantScoped::MissingTenantError (Current.tenant missing) or silently
# return nothing (GUC missing), neither of which points clearly at "you
# only set half of this." Doing both together in one place means nothing
# calling this can accidentally skip half of it.
#
# Uses plain SET + an explicit RESET in `ensure`, not SET LOCAL wrapped in
# a transaction. SET LOCAL only lasts until the *outer* transaction ends —
# with nested/savepoint transactions (which Rails creates routinely) that
# boundary doesn't line up with "end of this request/job", so a value set
# with SET LOCAL can silently outlive the block that set it. Plain SET +
# RESET in ensure is deterministic regardless of transaction nesting.
module SetsDatabaseTenantContext
  extend ActiveSupport::Concern

  private

  def with_database_tenant_context(tenant)
    connection = ActiveRecord::Base.connection
    Current.tenant = tenant
    connection.execute("SET app.current_tenant_id = #{tenant.id.to_i}") if tenant
    yield
  ensure
    connection.execute("RESET app.current_tenant_id") if tenant
    Current.tenant = nil
  end
end
