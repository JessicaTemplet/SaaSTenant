# Bounds FugueReplay's cost: without this, rebuilding a document's tree
# means replaying its ENTIRE op history on every single insert/delete,
# which gets slower the longer a document lives. A snapshot lets replay
# start from "tree state as of op N" and only replay what came after.
#
# snapshot_through_op is a real reference (not just an id column) so it's
# always a valid, existing op — never a stale pointer into ops that could
# theoretically be pruned later.
class AddFugueSnapshotToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :documents, :fugue_snapshot, :jsonb
    add_reference :documents, :snapshot_through_op, foreign_key: { to_table: :document_ops }, null: true
  end
end
