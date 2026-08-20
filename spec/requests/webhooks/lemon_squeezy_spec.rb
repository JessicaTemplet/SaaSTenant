require "rails_helper"

RSpec.describe "LemonSqueezy webhooks", type: :request do
  let(:secret) { "whtest_secret" }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:lemon_squeezy, :webhook_secret).and_return(secret)
  end

  def signed_post(payload, secret_override: secret, event_id: "evt_1", event_name: "subscription_created")
    body = payload.to_json
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret_override, body)

    post "/webhooks/lemon_squeezy",
      params: body,
      headers: {
        "Content-Type" => "application/json",
        "X-Signature"  => signature,
        "X-Event-Name" => event_name,
        "X-Event-Id"   => event_id
      }
  end

  it "accepts a correctly signed payload and records it" do
    expect {
      signed_post({ "meta" => { "event_name" => "subscription_created" } })
    }.to change(WebhookEvent, :count).by(1)

    expect(response).to have_http_status(:ok)

    event = WebhookEvent.last
    expect(event.source).to eq("lemon_squeezy")
    expect(event.external_id).to eq("evt_1")
    expect(event).to be_processed
  end

  it "rejects a payload with an invalid signature" do
    expect {
      signed_post({ "meta" => {} }, secret_override: "wrong_secret")
    }.not_to change(WebhookEvent, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it "is idempotent for a repeated provider event id" do
    signed_post({ "meta" => { "event_name" => "subscription_created" } }, event_id: "evt_dupe")

    expect {
      signed_post({ "meta" => { "event_name" => "subscription_created" } }, event_id: "evt_dupe")
    }.not_to change(WebhookEvent, :count)

    expect(response).to have_http_status(:ok)
  end

  it "rejects a payload with no resolvable event id" do
    body = { "meta" => {} }.to_json
    signature = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, body)

    post "/webhooks/lemon_squeezy",
      params: body,
      headers: { "Content-Type" => "application/json", "X-Signature" => signature }

    expect(response).to have_http_status(:unprocessable_content)
  end
end
