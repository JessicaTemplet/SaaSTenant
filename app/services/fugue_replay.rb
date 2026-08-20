# Rebuilds a Fugue instance for a document from its persisted op log —
# and, once a document has enough history, from a snapshot plus only the
# ops since that snapshot, rather than the full log every time. See
# lib/fugue.rb (#to_snapshot/.from_snapshot) for the serialization side of
# this.
#
# All ops for a document are decided by this one server-authoritative
# replica ("server") — see DocumentChannel, which serializes access per
# document via a row lock before ever calling into Fugue. That's what
# makes it safe to replay in plain `created_at` order here: for a
# genuinely multi-writer CRDT this would NOT be a valid causal order, but
# for this design it's simply the actual order the server decided each op
# in, since no two ops for the same document are ever decided
# concurrently.
class FugueReplay
  REPLICA_ID = "server"
  SNAPSHOT_INTERVAL = 50 # ops between snapshots

  def self.build(document)
    new(document).tree
  end

  def initialize(document)
    @document = document
  end

  def tree
    fugue = starting_point
    ops_since_snapshot.each { |record| fugue.apply_op(to_fugue_op(record)) }

    # restore_counter! only ever increases the counter, so it's safe to
    # pass the TOTAL insert count regardless of whether we started from a
    # snapshot or from scratch — no need to track "inserts since snapshot"
    # separately.
    fugue.restore_counter!(@document.document_ops.where(op_type: "insert").count)
    fugue
  end

  # Call after persisting a new op. Cheap to call unconditionally — it's a
  # no-op unless enough ops have accumulated since the last snapshot, so
  # callers don't need to reason about the interval themselves.
  def maybe_snapshot!(fugue)
    latest_op = @document.document_ops.order(:created_at).last
    return unless latest_op
    return if @document.snapshot_through_op_id == latest_op.id

    pending = @document.document_ops.where("document_ops.id > ?", @document.snapshot_through_op_id || 0).count
    return if pending < SNAPSHOT_INTERVAL

    @document.update!(fugue_snapshot: fugue.to_snapshot, snapshot_through_op_id: latest_op.id)
  end

  private

  def starting_point
    return Fugue.new(replica_id: REPLICA_ID) unless @document.fugue_snapshot.present?

    Fugue.from_snapshot(@document.fugue_snapshot)
  end

  def ops_since_snapshot
    scope = @document.document_ops.order(:created_at)
    scope = scope.where("document_ops.id > ?", @document.snapshot_through_op_id) if @document.snapshot_through_op_id
    scope
  end

  def to_fugue_op(record)
    case record.op_type
    when "insert"
      Fugue::InsertOp.new(
        type: :insert,
        id: [ record.fugue_replica, record.fugue_counter ],
        value: record.value,
        parent_id: record.parent_replica ? [ record.parent_replica, record.parent_counter ] : nil,
        side: record.side&.to_sym,
      )
    when "delete"
      Fugue::DeleteOp.new(type: :delete, id: [ record.fugue_replica, record.fugue_counter ])
    else
      raise ArgumentError, "unknown persisted op_type: #{record.op_type.inspect}"
    end
  end
end
