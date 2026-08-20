require "rails_helper"

RSpec.describe "Cross-tenant session isolation", type: :request do
  let(:tenant_a) { create(:tenant, subdomain: "acme") }
  let(:tenant_b) { create(:tenant, subdomain: "beta") }

  def sign_in_as(tenant, email, password)
    host! "#{tenant.subdomain}.example.com"
    post session_path, params: { email_address: email, password: password }
  end

  it "signs in successfully on the correct tenant subdomain" do
    Current.tenant = tenant_a
    create(:user, tenant: tenant_a, email_address: "owner@acme.test",
                  password: "password123", password_confirmation: "password123")
    Current.tenant = nil

    sign_in_as(tenant_a, "owner@acme.test", "password123")
    expect(response).to redirect_to(tenant_root_path)
  end

  it "rejects the wrong password" do
    Current.tenant = tenant_a
    create(:user, tenant: tenant_a, email_address: "owner@acme.test",
                  password: "password123", password_confirmation: "password123")
    Current.tenant = nil

    sign_in_as(tenant_a, "owner@acme.test", "wrong-password")
    expect(response).to redirect_to(new_session_path)
  end

  it "does not resume a session under a different tenant's subdomain" do
    Current.tenant = tenant_a
    create(:user, tenant: tenant_a, email_address: "owner@acme.test",
                  password: "password123", password_confirmation: "password123")
    Current.tenant = nil

    sign_in_as(tenant_a, "owner@acme.test", "password123")
    expect(response).to redirect_to(tenant_root_path)

    # Same browser session cookie carried over, but now against tenant_b's
    # subdomain — this must NOT resume as owner@acme.test under tenant_b.
    host! "#{tenant_b.subdomain}.example.com"
    get dashboard_path

    expect(response).to redirect_to(new_session_path)
  end

  it "authenticates the same email independently per tenant" do
    Current.tenant = tenant_a
    create(:user, tenant: tenant_a, email_address: "shared@example.test",
                  password: "tenant-a-password", password_confirmation: "tenant-a-password")
    Current.tenant = tenant_b
    create(:user, tenant: tenant_b, email_address: "shared@example.test",
                  password: "tenant-b-password", password_confirmation: "tenant-b-password")
    Current.tenant = nil

    sign_in_as(tenant_a, "shared@example.test", "tenant-b-password")
    expect(response).to redirect_to(new_session_path) # wrong password for THIS tenant's user

    sign_in_as(tenant_a, "shared@example.test", "tenant-a-password")
    expect(response).to redirect_to(tenant_root_path)
  end

  it "returns 404 for an unknown subdomain" do
    host! "doesnotexist.example.com"
    get dashboard_path
    expect(response).to have_http_status(:not_found)
  end
end
