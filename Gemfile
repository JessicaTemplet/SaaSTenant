source "https://rubygems.org"

ruby "4.0.6"

gem "rails", "~> 8.1.0"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "bcrypt", "~> 3.1.7"      # required by has_secure_password (Rails 8 native auth)

gem "propshaft"               # asset pipeline — needed for stylesheet_link_tag etc.
gem "importmap-rails"         # JS via ESM import maps, no Node toolchain required
gem "turbo-rails"             # Hotwire: SPA-like navigation
gem "stimulus-rails"          # Hotwire: lightweight JS controllers
gem "jbuilder"                # JSON view templates, for any API responses later

gem "solid_cache"             # Rails 8 default cache store (DB-backed)
gem "solid_queue"             # Rails 8 default job backend (DB-backed)
gem "solid_cable"             # Rails 8 default Action Cable adapter (DB-backed, no Redis)
gem "sqlite3", "~> 2.1"       # storage for the solid_cache/queue/cable satellite DBs (see database.yml) — primary stays on pg

gem "kamal", require: false   # deploy via `kamal deploy` — see config/deploy.yml
gem "bootsnap", require: false
gem "fiddle" # silences a Ruby 4.0 default-gems warning triggered by reline/irb
gem "tzinfo-data", platforms: %i[windows jruby]

group :development, :test do
  gem "debug", platforms: %i[mri windows]
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "brakeman", require: false           # static security analysis
  gem "bundler-audit", require: false      # audits gem deps for known CVEs
  gem "rubocop-rails-omakase", require: false # style — the bin/rubocop that got copied in expects this
end

group :development do
  gem "web-console"
end

group :test do
  gem "webmock" # for stubbing LemonSqueezy webhook signature tests
end
