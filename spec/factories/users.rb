FactoryBot.define do
  factory :user do
    tenant
    sequence(:email_address) { |n| "user#{n}@example.test" }
    password              { "password123" }
    password_confirmation { "password123" }
    role                  { "member" }
  end
end
