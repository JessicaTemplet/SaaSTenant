class Document < ApplicationRecord
  include TenantScoped

  belongs_to :tenant
  belongs_to :snapshot_through_op, class_name: "DocumentOp", optional: true
  has_many :document_ops, -> { order(:created_at) }, dependent: :destroy

  validates :title, presence: true
end
