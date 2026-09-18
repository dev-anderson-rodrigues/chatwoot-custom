FactoryBot.define do
  factory :macro_execution do
    account
    macro
    inputs { {} }
    status { :pending }
    actions_run { 0 }
    actions_total { 0 }
  end
end
