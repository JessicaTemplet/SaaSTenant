class User < ApplicationRecord
  include TenantScoped # adds belongs_to :tenant + default_scope by Current.tenant

  # has_secure_password (with the reset_token: true default) already
  # registers a :password_reset token via generates_token_for, expiring in
  # 15 minutes, invalidated by password_salt changing on password update —
  # see ActiveModel::SecurePassword. Also gives us password_reset_token /
  # find_by_password_reset_token(!), used in PasswordsController.
  has_secure_password
  has_many :sessions, dependent: :destroy

  ROLES = %w[owner admin member].freeze

  normalizes :email_address, with: ->(email) { email.strip.downcase }

  validates :email_address, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :password, length: { minimum: 8 }, allow_nil: true

  # NOTE: the [tenant_id, email_address] uniqueness constraint lives at the
  # DB level (see migration) since default_scope makes an AR-level
  # uniqueness validation unreliable (it would only check within the
  # current tenant scope, which is what we want, but belt-and-suspenders
  # via DB index is what actually prevents races).
end
