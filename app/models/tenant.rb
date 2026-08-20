class Tenant < ApplicationRecord
  SUBDOMAIN_FORMAT = /\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\z/
  RESERVED_SUBDOMAINS = %w[www app api admin billing webhooks assets mail].freeze

  has_many :users, dependent: :destroy
  has_many :documents, dependent: :destroy

  before_validation { subdomain&.downcase!&.strip! }

  validates :name, presence: true
  validates :subdomain,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: SUBDOMAIN_FORMAT },
            exclusion: { in: RESERVED_SUBDOMAINS },
            length: { minimum: 2, maximum: 63 }
end
