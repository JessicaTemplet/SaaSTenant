# One row per Fugue op (insert or delete) — see lib/fugue.rb. Immutable
# once written; the log itself is the source of truth for a document's
# content, replayed by app/services/fugue_replay.rb.
class DocumentOp < ApplicationRecord
  include TenantScoped

  belongs_to :tenant
  belongs_to :document

  validates :op_type, inclusion: { in: %w[insert delete] }
  validates :fugue_replica, presence: true
  validates :fugue_counter, presence: true

  # Transient, not a DB column. DocumentChannel sets this right after
  # persisting an op — it already knows the resolved visible-text position
  # from the Fugue call that produced it — so the broadcast can tell a
  # thin client exactly where a character landed without that client ever
  # needing to walk the CRDT tree itself. Only ever valid on the
  # in-memory instance that was just created; never set when loading an
  # existing DocumentOp from the database.
  attr_accessor :resolved_index
end
