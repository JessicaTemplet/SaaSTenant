# Real-time collaborative editing over a document's Fugue CRDT — see
# lib/fugue.rb, app/services/fugue_replay.rb.
#
# Every action here re-establishes tenant context itself via
# with_database_tenant_context, rather than relying on anything set at
# Connection#connect time. ActionCable reuses a thread pool across
# messages on the same long-lived socket, so context from connect
# wouldn't reliably still be correct by the time a later message is
# processed — see the comment on ApplicationCable::Connection#resolve_tenant!.
#
# Wire protocol:
#   client -> server (via subscription.send, NOT .perform — this channel
#   only defines the low-level `receive`, not a named action):
#     { type: "insert", index: Integer, value: String, client_op_id: String }
#     { type: "delete", index: Integer, client_op_id: String }
#   client_op_id is optional and purely for the sender's own echo
#   suppression — never persisted, just threaded back through onto the
#   broadcast of whatever op(s) that intent produced.
#
#   server -> client, on subscribe:
#     { type: "init", text: String }
#   The client's whole starting state is just the current resolved text —
#   not the raw op log, which would need the client to walk the CRDT tree
#   itself just to know where each historical op landed. Live ops after
#   this DO carry a resolved index, computed once by the server at the
#   moment it's known, same reasoning.
#
#   server -> client, broadcast per resulting op:
#     { type: "insert", index: Integer, value: String, id: [...], client_op_id: String|nil }
#     { type: "delete", index: Integer, id: [...], client_op_id: String|nil }
class DocumentChannel < ApplicationCable::Channel
  include SetsDatabaseTenantContext

  def subscribed
    with_database_tenant_context(tenant) do
      document = tenant.documents.find_by(id: params[:document_id])
      return reject unless document

      stream_for document
      transmit({ type: "init", text: FugueReplay.build(document).to_s })
    end
  end

  def receive(data)
    with_database_tenant_context(tenant) do
      document = tenant.documents.find_by(id: params[:document_id])
      return unless document

      apply_intent!(document, data).each do |op|
        DocumentChannel.broadcast_to(document, serialize(op, client_op_id: data["client_op_id"]))
      end
    end
  end

  private

  def tenant
    @tenant ||= Tenant.find(tenant_id)
  end

  # Locks the document row for the duration of the position decision(s) +
  # persist, so two clients racing to edit the same document — even from
  # different Puma processes — get serialized here rather than both
  # deciding a position against the same stale tree state. If anything
  # raises partway through (e.g. a stale index mid-paste), the whole
  # transaction rolls back — one client intent is persisted atomically or
  # not at all, never partially.
  #
  # Returns an array of persisted DocumentOp records — usually one, but a
  # multi-character insert (a paste) becomes several single-character ops,
  # since Fugue's visible_index counts characters and a value spanning
  # more than one would silently break that invariant for every later op.
  def apply_intent!(document, data)
    document.with_lock do
      replay = FugueReplay.new(document)
      fugue  = replay.tree

      persisted =
        case data["type"]
        when "insert" then apply_insert!(fugue, document, data)
        when "delete" then apply_delete!(fugue, document, data)
        else []
        end

      replay.maybe_snapshot!(fugue) if persisted.any?
      persisted
    end
  rescue ArgumentError, IndexError
    # Stale client index (e.g. it raced a delete/insert it hasn't seen
    # yet) — drop the op(s) rather than crash the channel. The client
    # will get back in sync from the next broadcast either way.
    []
  end

  def apply_insert!(fugue, document, data)
    index      = data["index"].to_i
    characters = data["value"].to_s.chars
    return [] if characters.empty?

    characters.each_with_index.map do |char, offset|
      resolved_index = index + offset
      persist!(document, fugue.insert_at(resolved_index, char), resolved_index)
    end
  end

  def apply_delete!(fugue, document, data)
    resolved_index = data["index"].to_i
    [ persist!(document, fugue.delete_at(resolved_index), resolved_index) ]
  end

  def persist!(document, op, resolved_index)
    record = document.document_ops.create!(
      op_type:        op.type.to_s,
      fugue_replica:  op.id.first.to_s,
      fugue_counter:  op.id.last,
      value:          op.respond_to?(:value) ? op.value : nil,
      parent_replica: op.respond_to?(:parent_id) ? op.parent_id&.first&.to_s : nil,
      parent_counter: op.respond_to?(:parent_id) ? op.parent_id&.last : nil,
      side:           op.respond_to?(:side) ? op.side&.to_s : nil,
    )
    record.resolved_index = resolved_index
    record
  end

  def serialize(op, client_op_id: nil)
    payload = {
      type: op.op_type,
      id: [ op.fugue_replica, op.fugue_counter ],
      value: op.value,
      index: op.resolved_index,
      parent_id: op.parent_replica ? [ op.parent_replica, op.parent_counter ] : nil,
      side: op.side
    }
    payload[:client_op_id] = client_op_id if client_op_id
    payload
  end
end
