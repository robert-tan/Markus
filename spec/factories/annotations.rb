FactoryBot.define do
  factory :annotation, class: Annotation do
    association :submission_file, factory: :submission_file
    association :annotation_text, factory: :annotation_text
    line_start { 0 }
    line_end { 1 }
    x1 { 0 }
    x2 { 0 }
    y1 { 0 }
    y2 { 0 }
    type { 'text' }
    sequence(:annotation_number) { |n| n }
    is_remark { false }
    page { 0 }
    column_start { 0 }
    column_end { 0 }
    creator_type { 'ta' }
    creator_id { 0 }
  end
end
