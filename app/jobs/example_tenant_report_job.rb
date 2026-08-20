# Example only — shows the pattern: a job's `perform` never needs to know
# about tenant_id itself. Current.tenant is already restored by
# ApplicationJob's around_perform by the time this runs, so User (and any
# other TenantScoped model) is scoped exactly like it would be in a
# request from that tenant.
class ExampleTenantReportJob < ApplicationJob
  def perform
    Rails.logger.info("Generating report for #{Current.tenant.name}: #{User.count} users")
    # Any TenantScoped query here is automatically scoped to the tenant
    # that was current when this job was enqueued — no tenant_id param
    # needed in the method signature above.
  end
end
