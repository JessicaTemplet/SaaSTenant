# Include in every model that carries a tenant_id column.
#
# Design intent: make it hard to *accidentally* leak data across tenants.
# - default_scope filters every read to Current.tenant, when one is set.
# - belongs_to :tenant is required, so records can't exist tenant-less.
# - `TenantScoped.unscoped_for_system!` is the explicit, auditable escape
#   hatch for background jobs / admin tools that must cross tenants.
module TenantScoped
  extend ActiveSupport::Concern

  class MissingTenantError < StandardError; end

  included do
    belongs_to :tenant

    default_scope do
      if Current.tenant
        where(tenant_id: Current.tenant.id)
      elsif ActiveSupport::IsolatedExecutionState[:tenant_scope_bypassed]
        all
      else
        raise MissingTenantError,
          "#{name} was queried with no Current.tenant set. " \
          "Set Current.tenant, or wrap the call in TenantScoped.unscoped_for_system!"
      end
    end

    before_validation :assign_current_tenant, on: :create
  end

  class_methods do
    # Explicit, auditable escape hatch. Use ONLY in system/admin contexts
    # (e.g. a Sidekiq job that fans out across all tenants), never inside
    # a normal request cycle.
    #
    # Flips both the Ruby-level scope AND the DB-level RLS bypass GUC —
    # once FORCE ROW LEVEL SECURITY is on (see the RLS migration), the
    # Postgres policy is what actually decides row visibility, so `unscoped`
    # alone would just return zero rows here rather than bypassing anything.
    def unscoped_for_system!
      ActiveSupport::IsolatedExecutionState[:tenant_scope_bypassed] = true
      connection = ActiveRecord::Base.connection
      connection.execute("SET app.bypass_rls = 'on'")
      unscoped { yield }
    ensure
      connection.execute("RESET app.bypass_rls")
      ActiveSupport::IsolatedExecutionState[:tenant_scope_bypassed] = false
    end
  end

  private

  def assign_current_tenant
    self.tenant_id ||= Current.tenant&.id
  end
end
