# ActiveSupport::CurrentAttributes resets automatically around real
# requests, jobs, and console commands (via Rails' executor callbacks),
# but RSpec model/unit examples don't go through that executor — so
# without this, Current.tenant set in one example can silently leak
# into the next one and mask missing `Current.tenant =` setup in tests
# that should be exercising TenantScoped's raise-when-unset behavior.
RSpec.configure do |config|
  config.after do
    Current.reset
  end
end
