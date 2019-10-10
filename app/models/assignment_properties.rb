# Internal model used to link assignment attributes with the assignment STI model
class AssignmentProperties < ApplicationRecord
  belongs_to :assignment, dependent: :destroy, foreign_key: :assessment_id
  validates_presence_of :assignment

  validates_numericality_of :group_min, only_integer: true, greater_than: 0
  validates_numericality_of :group_max, only_integer: true, greater_than: 0

  validates :repository_folder, presence: true, exclusion: { in: Repository.get_class.reserved_locations }
  validate :repository_folder_unchanged, on: :update
  validates_presence_of :group_min
  validates_presence_of :group_max
  validates_presence_of :notes_count
  # "validates_presence_of" for boolean values.
  validates_inclusion_of :allow_web_submits, in: [true, false]
  validates_inclusion_of :vcs_submit, in: [true, false]
  validates_inclusion_of :display_grader_names_to_students, in: [true, false]
  validates_inclusion_of :display_median_to_students, in: [true, false]
  validates_inclusion_of :has_peer_review, in: [true, false]
  validates_inclusion_of :assign_graders_to_criteria, in: [true, false]
  validates_inclusion_of :student_form_groups, in: [true, false]
  validates_inclusion_of :group_name_autogenerated, in: [true, false]
  validates_inclusion_of :group_name_displayed, in: [true, false]
  validates_inclusion_of :invalid_override, in: [true, false]
  validates_inclusion_of :section_groups_only, in: [true, false]
  validates_inclusion_of :only_required_files, in: [true, false]
  validates_inclusion_of :allow_web_submits, in: [true, false]
  validates_inclusion_of :section_due_dates_type, in: [true, false]
  validates_inclusion_of :assign_graders_to_criteria, in: [true, false]
  validates_inclusion_of :unlimited_tokens, in: [true, false]
  validates_inclusion_of :non_regenerating_tokens, in: [true, false]

  validates_inclusion_of :enable_test, in: [true, false]
  validates_inclusion_of :enable_student_tests, in: [true, false], if: :enable_test
  validates_inclusion_of :non_regenerating_tokens, in: [true, false], if: :enable_student_tests
  validates_inclusion_of :unlimited_tokens, in: [true, false], if: :enable_student_tests
  validates_presence_of :token_start_date, if: :enable_student_tests
  with_options if: -> { :enable_student_tests && !:unlimited_tokens } do |assignment|
    assignment.validates :tokens_per_period,
                         presence: true,
                         numericality: { only_integer: true,
                                         greater_than_or_equal_to: 0 }
  end
  with_options if: -> { !:non_regenerating_tokens && :enable_student_tests && !:unlimited_tokens } do |assignment|
    assignment.validates :token_period,
                         presence: true,
                         numericality: { greater_than: 0 }
  end

  validates_inclusion_of :scanned_exam, in: [true, false]

  validate :minimum_number_of_groups

  def minimum_number_of_groups
    return unless (group_max && group_min) && group_max < group_min
    errors.add(:group_max, 'must be greater than the minimum number of groups')
    false
  end

  def repository_folder_unchanged
    return unless repository_folder_changed?
    errors.add(:repo_folder_change, 'repository folder should not be changed once an assignment has been created')
    false
  end

  def update_permissions_if_vcs_changed
    return unless saved_change_to_vcs_submit?
    Repository.get_class.update_permissions
  end
end
