namespace :db do
  desc 'Sets up environment to test the autotester'
  task autotest: :environment do
    include AutomatedTestsHelper
    Rake::Task['markus:setup_autotest'].invoke
    puts 'Set up testing environment for autotest'
    AutotestTestersJob.perform_now
    autotest_files_dirs = Dir.glob(File.join('db', 'data', 'autotest_files', '*'))
    autotest_files_dirs.each do |dir_path|
      AutotestSetup.new dir_path
    end
  end
end

class AutotestSetup
  def initialize(root_dir)
    testers_schema_path = File.join(MarkusConfigurator.autotest_client_dir, 'testers.json')

    # setup instance variables (mostly paths to directories)
    @assg_short_id = "autotest_#{File.basename(root_dir)}"
    script_dir = File.join(root_dir, 'script_files')
    @test_scripts = Dir.glob(File.join(script_dir, '*'))
    @specs_file = File.join(root_dir, 'specs.json')
    @specs_data = JSON.parse(File.open(@specs_file, &:read))

    @student_dir = File.join(root_dir, 'student_files')
    @student_files = Dir.glob(File.join(@student_dir, '*'))

    @assignment = create_new_assignment

    @schema_data = JSON.parse(File.open(testers_schema_path, &:read))
    fill_in_schema_data!(@schema_data, @test_scripts, @assignment)

    clear_old_files
    move_test_script_files

    # setup other elements required for autotesting
    create_marking_scheme
    create_criteria
    create_student
    process_schema_data
  end

  def create_new_assignment
    rule = NoLateSubmissionRule.new
    assignment_stat = AssignmentStat.new
    Assignment.create(
      short_identifier: @assg_short_id,
      description: 'Assignment for testing the autotester',
      message: '',
      due_date: 1.week.from_now,
      assignment_properties_attributes: {
        group_min: 1,
        group_max: 1,
        student_form_groups: false,
        group_name_autogenerated: false,
        group_name_displayed: false,
        repository_folder: @assg_short_id,
        allow_web_submits: true,
        display_grader_names_to_students: false,
        allow_remarks: false,
        enable_test: true,
        tokens_per_period: 0,
        token_start_date: Time.now,
        token_period: 1,
        only_required_files: false,
        enable_student_tests: true,
        unlimited_tokens: true
      },
      submission_rule: rule,
      assignment_stat: assignment_stat
    )
    Assignment.find_by_short_identifier(@assg_short_id)
  end

  def clear_old_files
    # remove existing files to create room for new ones
    # remove test scripts
    autotest_dir = @assignment.autotest_path
    FileUtils.remove_dir(autotest_dir, force: true)
  end

  def move_test_script_files
    # create new directories to put new autotest files into
    test_file_destination = @assignment.autotest_files_dir
    FileUtils.makedirs test_file_destination

    # copy test scripts and specs files into the destination directory
    FileUtils.cp @test_scripts, test_file_destination
    FileUtils.cp @specs_file, @assignment.autotest_path
  end

  def create_marking_scheme
    # make one marking scheme for autotesting in general
    # give all assignments an equal marking weight (1)
    marking_scheme = MarkingScheme.find_or_create_by(name: 'Scheme Autotest')
    marking_weight = MarkingWeight.find_or_create_by(
      gradable_item_id: @assignment.id,
      weight: 1,
      is_assignment: true
    )
    marking_scheme.marking_weights << marking_weight
  end

  def create_criteria
    FlexibleCriterion.find_or_create_by(
      name: 'criteria',
      assessment_id: @assignment.id,
      position: 1,
      max_mark: 5,
      assigned_groups_count: nil
    )
  end

  def create_student
    student = User.add_user(Student, %w[aaaautotest Test Otto])
    student.create_group_for_working_alone_student(@assignment.id)
    group = Group.find_by group_name: student.user_name

    group.access_repo do |repo|
      transaction = repo.get_transaction(student.user_name)
      @student_files.each do |file_path|
        File.open(file_path, 'r') do |file|
          file_rel_path = Pathname.new(file_path).relative_path_from Pathname.new(@student_dir)
          repo_path = File.join(@assignment.assignment_properties.repository_folder, file_rel_path)
          transaction.add(repo_path, file.read, '')
        end
      end
      repo.commit(transaction)
    end
    grouping = Grouping.find_by_group_id_and_assessment_id(group, @assignment)
    # create new submission for each grouping
    time = @assignment.submission_rule.calculate_collection_time.localtime
    Submission.create_by_timestamp(grouping, time)
    # collect submission
    grouping.is_collected = true
    grouping.save
  end

  def process_schema_data
    Assignment.transaction do
      update_test_groups_from_specs(@assignment, @specs_data)
      upload_test_files
    end
  end

  def upload_test_files
    # send files for all hostnames because the
    # autotester uses the names as part of a hash key
    AutotestSpecsJob.perform_now('http://localhost:3000', @assignment)
    AutotestSpecsJob.perform_now('http://127.0.0.1:3000', @assignment)
    AutotestSpecsJob.perform_now('http://0.0.0.0:3000', @assignment)
  end
end
