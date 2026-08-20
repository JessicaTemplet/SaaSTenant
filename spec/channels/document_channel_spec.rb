require "rails_helper"

RSpec.describe DocumentChannel, type: :channel do
  include ActionCable::TestHelper

  let(:tenant_a) { create(:tenant) }
  let(:tenant_b) { create(:tenant) }
  let(:document) do
    Current.tenant = tenant_a
    create(:document, tenant: tenant_a)
  end
  let(:user_a) do
    Current.tenant = tenant_a
    create(:user, tenant: tenant_a)
  end

  before do
    document
    user_a
    Current.tenant = nil
    stub_connection(tenant_id: tenant_a.id, current_user: user_a)
  end

  it "streams for the document when it belongs to the connection's tenant" do
    subscribe(document_id: document.id)

    expect(subscription).to be_confirmed
    expect(subscription).to have_stream_for(document)
  end

  it "transmits the document's current resolved text on subscribe" do
    Current.tenant = tenant_a
    fugue = Fugue.new(replica_id: "server")
    op = fugue.insert_at(0, "a")
    document.document_ops.create!(
      op_type: "insert", fugue_replica: op.id.first.to_s, fugue_counter: op.id.last,
      value: "a", side: op.side.to_s,
    )
    Current.tenant = nil

    subscribe(document_id: document.id)

    expect(transmissions.last).to eq({ "type" => "init", "text" => "a" })
  end

  it "rejects subscribing to a document that belongs to a different tenant" do
    Current.tenant = tenant_b
    other_document = create(:document, tenant: tenant_b)
    Current.tenant = nil

    subscribe(document_id: other_document.id)

    expect(subscription).to be_rejected
  end

  it "persists a received insert and broadcasts the resulting op with its resolved index" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "insert", "index" => 0, "value" => "a"
    }.to have_broadcasted_to(document).with(
      hash_including("type" => "insert", "value" => "a", "index" => 0),
    )

    Current.tenant = tenant_a
    expect(document.document_ops.count).to eq(1)
  end

  it "echoes the client_op_id back on the broadcast, for the sender's own echo suppression" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "insert", "index" => 0, "value" => "a", "client_op_id" => "abc123"
    }.to have_broadcasted_to(document).with(hash_including("client_op_id" => "abc123"))
  end

  it "does not include client_op_id when the sender didn't send one" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "insert", "index" => 0, "value" => "a"
    }.to have_broadcasted_to(document).with(satisfy { |payload| !payload.key?("client_op_id") })
  end

  it "produces the correct final text across several sequential ops" do
    subscribe(document_id: document.id)

    perform :receive, "type" => "insert", "index" => 0, "value" => "a"
    perform :receive, "type" => "insert", "index" => 1, "value" => "c"
    perform :receive, "type" => "insert", "index" => 1, "value" => "b"

    Current.tenant = tenant_a
    expect(FugueReplay.build(document).to_s).to eq("abc")
  end

  it "drops a stale op instead of raising when the client's index no longer exists" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "delete", "index" => 0
    }.not_to raise_error

    Current.tenant = tenant_a
    expect(document.document_ops.count).to eq(0)
  end

  it "splits a multi-character insert (a paste) into individual character ops with sequential indices" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "insert", "index" => 0, "value" => "abc"
    }.to have_broadcasted_to(document).exactly(3).times

    Current.tenant = tenant_a
    expect(document.document_ops.count).to eq(3)
    expect(FugueReplay.build(document).to_s).to eq("abc")
  end

  it "drops an insert with an empty value instead of persisting a blank character" do
    subscribe(document_id: document.id)

    expect {
      perform :receive, "type" => "insert", "index" => 0, "value" => ""
    }.not_to have_broadcasted_to(document)

    Current.tenant = tenant_a
    expect(document.document_ops.count).to eq(0)
  end

  it "rolls back an entire paste atomically when its starting index is out of range" do
    subscribe(document_id: document.id)

    # Index 5 doesn't exist in an empty document, so this fails on the
    # very first character. Nothing from the batch should land, not even
    # a partial prefix.
    expect {
      perform :receive, "type" => "insert", "index" => 5, "value" => "abc"
    }.not_to have_broadcasted_to(document)

    Current.tenant = tenant_a
    expect(document.document_ops.count).to eq(0)
  end
end
