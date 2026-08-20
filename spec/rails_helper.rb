require "spec_helper"
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rspec/rails"
require "webmock/rspec"

# Loads everything in spec/support/, including current_attributes.rb —
# without this require, that file's RSpec.configure block never runs.
Dir[Rails.root.join("spec", "support", "**", "*.rb")].sort.each { |f| require f }

# Gemfile pulls in webmock specifically for the LemonSqueezy webhook specs;
# putting it to use here as a safety net too, so any spec that accidentally
# tries to hit the real network fails loud instead of hanging or flaking.
WebMock.disable_net_connect!(allow_localhost: true)

# Keeps the test database schema in sync with db/schema.rb automatically —
# without this, a fresh `db:migrate` (which only touches the development
# database) leaves the test database empty until something loads the
# schema into it.
ActiveRecord::Migration.maintain_test_schema!

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # Lets specs call create(:x) / build(:x) directly instead of
  # FactoryBot.create(:x) — factory_bot_rails doesn't wire this in on its
  # own, it has to be added explicitly.
  config.include FactoryBot::Syntax::Methods
end
