class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :title, null: false, default: "Untitled"
      t.timestamps
    end
  end
end
