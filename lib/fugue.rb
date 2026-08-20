# frozen_string_literal: true

# Fugue â€” a list/text CRDT that avoids the interleaving anomaly plain
# RGA/WOOT have when two replicas concurrently insert at the same position.
#
# Source: Weidner & Kleppmann, "The Art of the Fugue: Minimizing
# Interleaving in Collaborative Text Editing" (arXiv:2305.00583),
# Algorithm 1. This is a direct implementation of that pseudocode, not an
# approximation â€” same-side sibling ordering, tombstone-inclusive origin
# lookup, and the has-right-child test for left-vs-right placement all
# follow the paper exactly (verified against the paper's Theorem 1 proof,
# not just Algorithm 1's pseudocode, after an OCR'd source initially had a
# negation flipped), since those are precisely the details that reintroduce
# interleaving if fudged.
#
# Tree model: every inserted value is a node with (id, parent_id, side).
# Reading the document is an in-order traversal: left children (ascending
# id), self, right children (ascending id) â€” recursively.
#
# This class models ONE replica's state and does no networking of its own.
# `insert_at` / `delete_at` decide position locally and return the
# resulting op for the caller to broadcast; `apply_op` splices a node into
# the tree and is the ONLY code path that does so â€” used for a replica's
# own ops and for remote ops alike, so there's one place that can be wrong
# instead of two that could silently diverge.
#
# Not thread-safe â€” @nodes is plain mutable state with no locking. Every
# caller in this app constructs a fresh instance scoped to one
# document.with_lock block and never shares it across threads; that's
# what actually keeps this safe, not anything in this class itself.
#
# Each node's `value` is expected to be a single atomic unit (one
# character, for this app) â€” DocumentChannel is what enforces that at the
# boundary, not this class, since Fugue itself is a general list CRDT and
# has no opinion on what a "character" is. A caller that inserts a
# multi-character string as one value will not break the tree, but every
# visible_index in and out of this class would then be counting op-chunks,
# not characters â€” silently wrong position semantics for any caller
# assuming character-level indexing.
class Fugue
  ROOT_ID = nil

  Node = Struct.new(:id, :value, :parent_id, :side, :left_children, :right_children, :tombstoned) do
    def initialize(id:, value:, parent_id:, side:, tombstoned: false)
      super(id, value, parent_id, side, [], [], tombstoned)
    end
  end

  InsertOp = Struct.new(:type, :id, :value, :parent_id, :side, keyword_init: true)
  DeleteOp = Struct.new(:type, :id, keyword_init: true)

  attr_reader :replica_id

  def initialize(replica_id:)
    @replica_id = replica_id
    @counter    = 0
    @nodes      = { ROOT_ID => Node.new(id: ROOT_ID, value: nil, parent_id: nil, side: nil) }
  end

  # Reconstructs a replica from a snapshot produced by #to_snapshot. Used
  # to avoid replaying a document's entire op history on every operation â€”
  # see FugueReplay, which pairs this with replaying only the ops that
  # came after the snapshot.
  def self.from_snapshot(snapshot)
    fugue = new(replica_id: snapshot["replica_id"] || snapshot[:replica_id])
    fugue.send(:restore_nodes!, snapshot["nodes"] || snapshot[:nodes])
    fugue.restore_counter!((snapshot["counter"] || snapshot[:counter]).to_i)
    fugue
  end

  # â”€â”€ Local operations: decide position, splice, return the op to broadcast â”€â”€

  def insert_at(visible_index, value)
    id          = next_id
    left_origin = node_before(visible_index)

    parent_id, side =
      if has_right_child?(left_origin)
        # leftOrigin already has a right subtree â€” its successor
        # (rightOrigin) must live inside that subtree, so becoming
        # rightOrigin's LEFT child threads the new node in between
        # them. Fugue paper, Algorithm 1 lines 27-28 / Figure 4(b).
        right_origin = successor_including_tombstones(left_origin)
        [ right_origin.id, :left ]
      else
        # leftOrigin has no right child yet â€” becoming its right child
        # directly makes the new node leftOrigin's immediate successor.
        # Algorithm 1 lines 25-26 / Figure 4(a).
        [ left_origin.id, :right ]
      end

    op = InsertOp.new(type: :insert, id: id, value: value, parent_id: parent_id, side: side)
    apply_op(op)
    op
  end

  def delete_at(visible_index)
    node = node_at(visible_index)
    op   = DeleteOp.new(type: :delete, id: node.id)
    apply_op(op)
    op
  end

  # â”€â”€ Applying an op â€” the single splice path, local or remote â”€â”€

  def apply_op(op)
    case op.type
    when :insert then apply_insert(op)
    when :delete then apply_delete(op)
    else raise ArgumentError, "unknown op type: #{op.type}"
    end
  end

  # â”€â”€ Reading the document â”€â”€

  def to_a
    full_traversal.reject(&:tombstoned).map(&:value)
  end

  def to_s
    to_a.join
  end

  def size
    to_a.size
  end

  # Advances the counter used to mint new ids, without touching tree state.
  # Needed when rebuilding a replica from a persisted op log: replaying ops
  # via apply_op doesn't consume the counter (only insert_at does), so
  # without this, a freshly-rebuilt replica's next LOCAL insert_at call
  # would mint an id that collides with one already in the log. Pass the
  # count of insert ops already replayed for this replica_id.
  def restore_counter!(n)
    @counter = n if n > @counter
  end

  # Plain-data snapshot of this replica's full state, JSON-round-trippable
  # (ids are 2-element arrays, which JSON preserves as nested arrays).
  # Pairs with .from_snapshot. See FugueReplay for how this is actually
  # used to bound replay cost.
  def to_snapshot
    {
      "replica_id" => replica_id,
      "counter" => @counter,
      "nodes" => @nodes.each_value.map do |n|
        {
          "id" => n.id,
          "value" => n.value,
          "parent_id" => n.parent_id,
          "side" => n.side&.to_s,
          "tombstoned" => n.tombstoned,
          "left_children" => n.left_children,
          "right_children" => n.right_children
        }
      end
    }
  end

  private

  def restore_nodes!(serialized_nodes)
    Array(serialized_nodes).each do |n|
      id = deserialize_id(n["id"] || n[:id])
      node = Node.new(
        id: id,
        value: n["value"] || n[:value],
        parent_id: deserialize_id(n["parent_id"] || n[:parent_id]),
        side: (n["side"] || n[:side])&.to_sym,
        tombstoned: n["tombstoned"] || n[:tombstoned] || false,
      )
      node.left_children.concat(Array(n["left_children"] || n[:left_children]).map { |c| deserialize_id(c) })
      node.right_children.concat(Array(n["right_children"] || n[:right_children]).map { |c| deserialize_id(c) })
      @nodes[id] = node
    end
  end

  def deserialize_id(raw)
    return nil if raw.nil?

    [ raw[0], raw[1] ]
  end

  def next_id
    id = [ replica_id, @counter ]
    @counter += 1
    id
  end

  # Fugue IDs are compared lexicographically as (replica_id, counter)
  # tuples. Ruby's Array#<=> does this natively as long as replica_id is
  # itself comparable within itself (all Strings, or all Integers).
  def id_less_than(a, b)
    (a <=> b).negative?
  end

  def apply_insert(op)
    node = Node.new(id: op.id, value: op.value, parent_id: op.parent_id, side: op.side)
    @nodes[op.id] = node

    parent      = @nodes.fetch(op.parent_id)
    sibling_ids = op.side == :right ? parent.right_children : parent.left_children

    idx = sibling_ids.find_index { |existing_id| id_less_than(op.id, existing_id) } || sibling_ids.size
    sibling_ids.insert(idx, op.id)
  end

  def apply_delete(op)
    @nodes.fetch(op.id).tombstoned = true
  end

  def has_right_child?(node)
    !node.right_children.empty?
  end

  # Flat in-order traversal (left children asc-id, self, right children
  # asc-id), tombstones included, ROOT itself excluded from the result.
  def full_traversal
    traverse_subtree(ROOT_ID)
  end

  def traverse_subtree(node_id)
    node   = @nodes.fetch(node_id)
    result = []
    node.left_children.each  { |id| result.concat(traverse_subtree(id)) }
    result << node unless node_id == ROOT_ID
    node.right_children.each { |id| result.concat(traverse_subtree(id)) }
    result
  end

  # Array#fetch on a NEGATIVE index doesn't raise â€” Ruby indexes arrays
  # from the end, so fetch(-1) silently returns the last element instead
  # of signaling "out of range." A negative visible_index reaching here
  # (a malformed or malicious client payload, say) would otherwise resolve
  # against some arbitrary existing node rather than failing loudly.
  def node_before(visible_index)
    raise IndexError, "negative visible_index: #{visible_index}" if visible_index.negative?
    return @nodes.fetch(ROOT_ID) if visible_index.zero?

    full_traversal.reject(&:tombstoned).fetch(visible_index - 1)
  end

  def node_at(visible_index)
    raise IndexError, "negative visible_index: #{visible_index}" if visible_index.negative?

    full_traversal.reject(&:tombstoned).fetch(visible_index)
  end

  # The next node after `origin_node` in the FULL traversal â€” tombstones
  # included â€” which is what keeps insertion points stable relative to
  # concurrent deletes. Only called when has_right_child?(origin_node) is
  # true, in which case this is guaranteed non-nil (it's the leftmost node
  # of origin_node's own right subtree).
  def successor_including_tombstones(origin_node)
    ordering = full_traversal
    return ordering.first if origin_node.id == ROOT_ID

    idx = ordering.index { |n| n.id == origin_node.id }
    ordering[idx + 1]
  end
end
