class ApplicationController < ActionController::Base
  include Authentication
  include SetsDatabaseTenantContext

  # Modern browser support only; skip if you need legacy browser support.
  allow_browser versions: :modern

  # One prepended around_action, not two separate before_actions. This has
  # to run — fully, tenant resolved AND the DB session GUC set — before
  # Authentication's require_authentication, because resuming a session
  # reads the `users` table, which is RLS-protected: without the GUC set
  # first, that read would return zero rows and every request would look
  # logged out.
  around_action :establish_tenant_context, prepend: true

  private

  def establish_tenant_context
    return yield if request.subdomain.blank? || request.subdomain == "www"

    Current.tenant = Tenant.find_by!(subdomain: request.subdomain)
    with_database_tenant_context(Current.tenant) { yield }
  rescue ActiveRecord::RecordNotFound
    render plain: "Not found", status: :not_found
  end
end
