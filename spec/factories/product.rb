FactoryBot.define do
  factory :product do
    name                { Faker::Name.name }
    trait :with_plan do
      stripe_plan_name  { SecureRandom.hex }
      paypal_plan_name  { SecureRandom.hex }
    end
    price_cents         { Faker::Number.number(digits: 4) }
  end
end
