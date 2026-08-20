require "rails_helper"

RSpec.describe "Registrations", type: :request do
  let(:tenant) { create(:tenant, subdomain: "acme") }

  before { host! "#{tenant.subdomain}.example.com" }

  it "makes the first user for a tenant the owner" do
    post registration_path, params: {
      user: { email_address: "first@example.test", password: "password123", password_confirmation: "password123" }
    }

    Current.tenant = tenant
    expect(User.find_by!(email_address: "first@example.test").role).to eq("owner")
  end

  it "makes a second user for the same tenant a member" do
    Current.tenant = tenant
    create(:user, tenant: tenant, role: "owner")
    Current.tenant = nil

    post registration_path, params: {
      user: { email_address: "second@example.test", password: "password123", password_confirmation: "password123" }
    }

    Current.tenant = tenant
    expect(User.find_by!(email_address: "second@example.test").role).to eq("member")
  end

  it "starts a new tenant's owner count independently of other tenants" do
    other_tenant = create(:tenant, subdomain: "beta")
    Current.tenant = other_tenant
    create(:user, tenant: other_tenant, role: "owner")
    Current.tenant = nil

    # `tenant` (acme) still has zero users even though `beta` already has
    # an owner — this registration should still become owner.
    post registration_path, params: {
      user: { email_address: "first@example.test", password: "password123", password_confirmation: "password123" }
    }

    Current.tenant = tenant
    expect(User.find_by!(email_address: "first@example.test").role).to eq("owner")
  end
end
