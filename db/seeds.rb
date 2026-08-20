tenant = Tenant.find_or_create_by!(subdomain: "acme") { |t| t.name = "Acme Inc." }

Current.tenant = tenant
User.find_or_create_by!(email_address: "owner@acme.test") do |u|
  u.password = "password123"
  u.password_confirmation = "password123"
  u.role = "owner"
end

puts "Seeded tenant '#{tenant.subdomain}' with owner@acme.test / password123"
puts "Visit: http://acme.localhost:3000"
