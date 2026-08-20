module Webhooks
  # Deliberately does NOT inherit from ApplicationController: webhooks
  # arrive with no session cookie and no tenant subdomain, so tenant
  # resolution and authentication (both required by ApplicationController)
  # don't apply here and would just 401/404 every request.
  class LemonSqueezyController < ActionController::Base
    skip_forgery_protection

    # Raw body is needed for HMAC verification, so read it before any
    # params parsing touches the request stream.
    before_action :verify_signature!

    def create
      payload = JSON.parse(request.raw_post)
      event_name = request.headers["X-Event-Name"].presence || payload.dig("meta", "event_name")
      external_id = request.headers["X-Event-Id"].presence || payload.dig("meta", "webhook_id") || payload.dig("data", "id")

      unless external_id.present?
        return head :unprocessable_entity
      end

      event = WebhookEvent.create_or_find_by!(source: "lemon_squeezy", external_id: external_id) do |e|
        e.event_name = event_name
        e.payload = payload
      end

      # Idempotency: if we've already recorded (and presumably processed)
      # this exact provider event, ack it again without reprocessing.
      # LemonSqueezy retries on anything but a 2xx, so duplicates WILL happen.
      if event.processed?
        return head :ok
      end

      process_event(event)
      event.mark_processed!

      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    # TODO: fill in real handling per event type once billing plans exist.
    # Keep this dumb-stupid-simple: look up the tenant/subscription record
    # from the payload (NOT from Current.tenant — there isn't one here),
    # and update state. Wrap multi-step updates in a transaction.
    def process_event(event)
      case event.event_name
      when "subscription_created", "subscription_updated", "subscription_cancelled",
           "subscription_resumed", "subscription_expired", "subscription_paused",
           "subscription_payment_success", "subscription_payment_failed"
        Rails.logger.info("[LemonSqueezy] #{event.event_name} received (id=#{event.external_id}) - handler not yet implemented")
        # e.g.: tenant = Tenant.find_by(id: event.payload.dig("meta", "custom_data", "tenant_id"))
      else
        Rails.logger.info("[LemonSqueezy] Unhandled event: #{event.event_name.inspect}")
      end
    end

    # LemonSqueezy signs the raw request body with HMAC-SHA256 using your
    # webhook signing secret, sent as the X-Signature header (hex digest).
    # Docs: https://docs.lemonsqueezy.com/help/webhooks#signing-requests
    def verify_signature!
      secret = Rails.application.credentials.dig(:lemon_squeezy, :webhook_secret)
      signature = request.headers["X-Signature"]

      if secret.blank? || signature.blank?
        return head :unauthorized
      end

      expected = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new("sha256"), secret, request.raw_post)

      unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)
        head :unauthorized
      end
    end
  end
end
