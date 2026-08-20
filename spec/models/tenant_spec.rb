require "rails_helper"

RSpec.describe Tenant do
  it "is invalid without a name" do
    tenant = build(:tenant, name: nil)
    expect(tenant).not_to be_valid
    expect(tenant.errors[:name]).to be_present
  end

  it "downcases and strips the subdomain before validation" do
    tenant = build(:tenant, subdomain: "  Acme  ")
    tenant.valid?
    expect(tenant.subdomain).to eq("acme")
  end

  it "rejects a subdomain that collides case-insensitively" do
    create(:tenant, subdomain: "acme")
    dupe = build(:tenant, subdomain: "ACME")

    expect(dupe).not_to be_valid
    expect(dupe.errors[:subdomain]).to include(a_string_matching(/taken/))
  end

  it "rejects reserved subdomains" do
    Tenant::RESERVED_SUBDOMAINS.each do |reserved|
      tenant = build(:tenant, subdomain: reserved)
      expect(tenant).not_to be_valid, "expected #{reserved.inspect} to be rejected"
    end
  end

  it "rejects subdomains with invalid characters" do
    tenant = build(:tenant, subdomain: "not_valid!")
    expect(tenant).not_to be_valid
  end

  it "rejects subdomains under 2 characters" do
    tenant = build(:tenant, subdomain: "a")
    expect(tenant).not_to be_valid
  end
end
