FactoryBot.define do
  factory :document do
    tenant
    sequence(:title) { |n| "Document #{n}" }
  end
end
