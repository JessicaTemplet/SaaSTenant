require "rails_helper"

# User is the only model that currently includes TenantScoped, so we
# exercise the concern through it rather than a throwaway test model —
# that's also exactly the code path production traffic hits.
RSpec.describe TenantScoped do
  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }

  def create_user_for(tenant)
    Current.tenant = tenant
    create(:user, tenant: tenant)
  end

  describe "default_scope" do
    it "raises when queried with no Current.tenant set" do
      create_user_for(tenant_a)
      Current.tenant = nil

      expect { User.count }.to raise_error(TenantScoped::MissingTenantError)
    end

    it "filters reads to Current.tenant" do
      user_a = create_user_for(tenant_a)
      user_b = create_user_for(tenant_b)

      Current.tenant = tenant_a
      expect(User.all).to contain_exactly(user_a)

      Current.tenant = tenant_b
      expect(User.all).to contain_exactly(user_b)
    end

    it "does not leak a record across tenants even by id" do
      user_b = create_user_for(tenant_b)

      Current.tenant = tenant_a
      expect(User.find_by(id: user_b.id)).to be_nil
    end
  end

  describe "#assign_current_tenant" do
    it "assigns tenant_id from Current.tenant on create when not explicitly set" do
      Current.tenant = tenant_a

      user = User.new(
        email_address:         "auto@example.test",
        password:              "password123",
        password_confirmation: "password123",
        role:                  "member",
      )
      user.save!

      expect(user.tenant_id).to eq(tenant_a.id)
    end
  end

  describe ".unscoped_for_system!" do
    it "allows reading across tenants inside the block" do
      user_a = create_user_for(tenant_a)
      user_b = create_user_for(tenant_b)
      Current.tenant = nil

      result = User.unscoped_for_system! { User.all.to_a }

      expect(result).to contain_exactly(user_a, user_b)
    end

    it "restores normal scoping after the block, including when the block raises" do
      create_user_for(tenant_a)
      Current.tenant = nil

      expect {
        User.unscoped_for_system! { raise "boom" }
      }.to raise_error("boom")

      # If the ensure in unscoped_for_system! didn't run, this would
      # incorrectly return rows instead of raising.
      expect { User.count }.to raise_error(TenantScoped::MissingTenantError)
    end
  end
end
