require "rails_helper"

RSpec.describe "Documents", type: :request do
  let(:tenant) { create(:tenant, subdomain: "acme") }
  let(:user) do
    Current.tenant = tenant
    create(:user, tenant: tenant, email_address: "owner@acme.test",
                  password: "password123", password_confirmation: "password123")
  end
  let(:document) do
    Current.tenant = tenant
    create(:document, tenant: tenant, title: "Test Doc")
  end

  before do
    user
    document
    Current.tenant = nil
    host! "#{tenant.subdomain}.example.com"
    post session_path, params: { email_address: "owner@acme.test", password: "password123" }
  end

  it "renders the document page with the editor mount point" do
    get document_path(document)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Test Doc")
    expect(response.body).to include('data-controller="document-editor"')
    expect(response.body).to include(document.id.to_s)
  end

  it "404s for a document belonging to a different tenant" do
    other_tenant = create(:tenant, subdomain: "beta")
    Current.tenant = other_tenant
    other_document = create(:document, tenant: other_tenant)
    Current.tenant = nil

    get document_path(other_document)

    expect(response).to have_http_status(:not_found)
  end
end
