class ApplicationJob < ActiveJob::Base
  include SetsDatabaseTenantContext

  # Captured at enqueue time, from whatever request/job enqueued this one.
  attr_accessor :tenant_id

  # NOTE: this goes into ActiveJob's serialized job payload via #serialize
  # below, not into `arguments`. Both Sidekiq's and Solid Queue's ActiveJob
  # adapters serialize the whole job (arguments + this) into the queue
  # backend and deserialize it back into a job instance before #perform
  # runs — so this travels with the job regardless of which queue adapter
  # you're on. Doing it this way (rather than prepending tenant_id onto
  # `arguments`) keeps `perform`'s method signature exactly what you'd
  # write for a single-tenant job.
  before_enqueue { self.tenant_id = Current.tenant&.id }

  around_perform do |job, block|
    tenant = job.tenant_id && Tenant.find_by(id: job.tenant_id)
    Current.tenant = tenant
    with_database_tenant_context(tenant) { block.call }
  ensure
    Current.reset
  end

  def serialize
    super.merge("tenant_id" => tenant_id)
  end

  def deserialize(job_data)
    super
    self.tenant_id = job_data["tenant_id"]
  end
end
