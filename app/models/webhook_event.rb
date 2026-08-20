# Not tenant-scoped: webhooks arrive before/outside any tenant request
# context, and a single provider event may ultimately affect a tenant
# resolved from its payload rather than from a subdomain.
class WebhookEvent < ApplicationRecord
  validates :source, :external_id, presence: true

  # Deliberately NOT also validating uniqueness here. The controller uses
  # create_or_find_by! for this, which is meant to survive a race (two
  # deliveries of the same event landing near-simultaneously) by catching
  # the database's unique-index violation and falling back to a find. An
  # application-level uniqueness validation runs BEFORE that INSERT is
  # even attempted, finds the existing row itself, and raises
  # ActiveRecord::RecordInvalid instead — a different exception that
  # create_or_find_by! doesn't catch, which defeats the whole point of
  # using it here. The db/migrate unique index on [:source, :external_id]
  # is what actually enforces this; that's the layer that should.
  scope :unprocessed, -> { where(processed_at: nil) }

  def processed?
    processed_at.present?
  end

  def mark_processed!
    update!(processed_at: Time.current)
  end
end
