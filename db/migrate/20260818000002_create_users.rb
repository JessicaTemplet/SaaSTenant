class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.references :tenant, null: false, foreign_key: true

      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :role, null: false, default: "member" # "owner" | "admin" | "member"

      t.timestamps
    end

    # Email must be unique *within* a tenant, not globally — the same
    # person's email can exist under two different tenants (companies).
    add_index :users, [ :tenant_id, :email_address ], unique: true
  end
end
