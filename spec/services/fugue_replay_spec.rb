require "rails_helper"

RSpec.describe FugueReplay do
  let(:tenant) { create(:tenant) }
  let(:document) { create(:document, tenant: tenant) }

  before { Current.tenant = tenant }

  def apply_and_persist(fugue, op)
    document.document_ops.create!(
      op_type:        op.type.to_s,
      fugue_replica:  op.id.first.to_s,
      fugue_counter:  op.id.last,
      value:          op.respond_to?(:value) ? op.value : nil,
      parent_replica: op.respond_to?(:parent_id) ? op.parent_id&.first&.to_s : nil,
      parent_counter: op.respond_to?(:parent_id) ? op.parent_id&.last : nil,
      side:           op.respond_to?(:side) ? op.side&.to_s : nil,
    )
  end

  it "rebuilds the document's text from the persisted op log" do
    fugue = Fugue.new(replica_id: "server")
    apply_and_persist(fugue, fugue.insert_at(0, "a"))
    apply_and_persist(fugue, fugue.insert_at(1, "b"))
    apply_and_persist(fugue, fugue.insert_at(2, "c"))

    expect(described_class.build(document).to_s).to eq("abc")
  end

  it "preserves deletes through replay" do
    fugue = Fugue.new(replica_id: "server")
    apply_and_persist(fugue, fugue.insert_at(0, "a"))
    apply_and_persist(fugue, fugue.insert_at(1, "b"))
    apply_and_persist(fugue, fugue.insert_at(2, "c"))
    apply_and_persist(fugue, fugue.delete_at(1))

    expect(described_class.build(document).to_s).to eq("ac")
  end

  it "restores the counter so the next local insert doesn't collide with a replayed id" do
    fugue = Fugue.new(replica_id: "server")
    apply_and_persist(fugue, fugue.insert_at(0, "a"))
    apply_and_persist(fugue, fugue.insert_at(1, "b"))

    rebuilt = described_class.build(document)
    new_op  = rebuilt.insert_at(2, "c")

    # Without restore_counter!, this would be ["server", 0] again â€” a
    # duplicate of the very first persisted op's id.
    expect(new_op.id).to eq([ "server", 2 ])
    expect(rebuilt.to_s).to eq("abc")
  end

  describe "#maybe_snapshot!" do
    before { stub_const("FugueReplay::SNAPSHOT_INTERVAL", 3) }

    it "does not snapshot before the interval is reached" do
      fugue = Fugue.new(replica_id: "server")
      2.times { |i| apply_and_persist(fugue, fugue.insert_at(i, "x")) }

      described_class.new(document).maybe_snapshot!(fugue)

      expect(document.reload.fugue_snapshot).to be_nil
    end

    it "snapshots once the interval is reached, pointing at the latest op" do
      fugue = Fugue.new(replica_id: "server")
      3.times { |i| apply_and_persist(fugue, fugue.insert_at(i, "x")) }
      latest = document.document_ops.order(:created_at).last

      described_class.new(document).maybe_snapshot!(fugue)
      document.reload

      expect(document.fugue_snapshot).to be_present
      expect(document.snapshot_through_op_id).to eq(latest.id)
    end

    it "a document rebuilt after a snapshot still produces the correct text" do
      fugue = Fugue.new(replica_id: "server")
      %w[a b c].each_with_index { |ch, i| apply_and_persist(fugue, fugue.insert_at(i, ch)) }

      described_class.new(document).maybe_snapshot!(fugue)
      document.reload

      apply_and_persist(fugue, fugue.insert_at(3, "d")) # one more op AFTER the snapshot

      expect(described_class.build(document).to_s).to eq("abcd")
    end
  end
end
