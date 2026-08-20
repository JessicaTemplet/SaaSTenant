class CreateWebhookEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :webhook_events do |t|
      t.string :source, null: false       # e.g. "lemon_squeezy"
      t.string :external_id, null: false  # provider's event/webhook id
      t.string :event_name
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at

      t.timestamps
    end

    # The core of idempotent webhook handling: a given provider event
    # can only ever be recorded (and thus processed) once.
    add_index :webhook_events, [ :source, :external_id ], unique: true
  end
end
