module ApplicationCable
  class Connection < ActionCable::Connection::Base
    include SetsDatabaseTenantContext

    identified_by :tenant_id, :current_user

    def connect
      tenant = resolve_tenant!
      user   = with_database_tenant_context(tenant) { resolve_user_for(tenant) }
      reject_unauthorized_connection unless user

      self.tenant_id    = tenant.id
      self.current_user = user
    end

    private

    # Resolved once here, purely to reject unauthorized sockets early and
    # to identify the connection for stream scoping. This does NOT keep
    # tenant context set for the connection's whole lifetime — ActionCable
    # reuses a thread pool across messages on the same long-lived socket,
    # so context set here would go stale or leak across tenants by the
    # time a later message arrives. Every channel action re-establishes
    # its own tenant context per-message instead (see DocumentChannel).
    def resolve_tenant!
      tenant = Tenant.find_by(subdomain: request.subdomain)
      reject_unauthorized_connection unless tenant
      tenant
    end

    def resolve_user_for(tenant)
      session_id = cookies.signed[:session_id]
      return nil unless session_id

      session = Session.find_by(id: session_id)
      user = session&.user
      user if user&.tenant_id == tenant.id
    end
  end
end
