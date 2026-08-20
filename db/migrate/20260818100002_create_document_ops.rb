# Append-only op log for a document's Fugue CRDT tree — see lib/fugue.rb
# and app/services/fugue_replay.rb. No updated_at: ops are never modified
# once written, only ever appended.
class CreateDocumentOps < ActiveRecord::Migration[8.1]
  def change
    create_table :document_ops do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true

      t.string :op_type, null: false        # "insert" | "delete"
      t.string :fugue_replica, null: false
      t.bigint :fugue_counter, null: false

      t.text :value                         # null for deletes
      t.string :parent_replica              # null for deletes
      t.bigint :parent_counter
      t.string :side                        # "left" | "right" — null for deletes

      t.datetime :created_at, null: false
    end

    # op_type is part of the unique key, not just document/replica/counter
    # — a delete op deliberately reuses the SAME fugue id as the insert
    # it's tombstoning (that's how CRDT tombstoning works), so without
    # op_type here, persisting the delete after the insert would collide
    # with it instead of adding a second row.
    add_index :document_ops, [ :document_id, :fugue_replica, :fugue_counter, :op_type ],
              unique: true, name: "index_document_ops_on_document_and_fugue_id"
    add_index :document_ops, [ :document_id, :created_at ]
  end
end
