require 'faker'

FactoryBot.define do
  factory :feedback_file_with_test_run, class: FeedbackFile do
    association :test_run, factory: :student_test_run
    filename { "#{Faker::Lorem.word}.txt" }
    mime_type { "text/plain" }
    file_content { Faker::Lorem.sentence }
  end
end
