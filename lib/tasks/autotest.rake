namespace :db do
  desc 'Sets up environment to test the autotester'
  task autotest: :environment do
    include AutomatedTestsHelper
    FileUtils.mkdir_p Rails.configuration.x.autotest.client_dir
    puts 'Set up testing environment for autotest'
    Rake::Task['markus:setup_autotest'].invoke

    # Create dummy student for autotest submissions.
    Student.find_or_create_by(user_name: 'aaaautotest', first_name: 'Test', last_name: 'Otto')

    autotest_files_dirs = Dir.glob(File.join('db', 'data', 'autotest_files', '*'))
    autotest_files_dirs.each do |dir_path|
      AutotestSetup.new dir_path
    end
  end
end

class AutotestSetup
  def initialize(root_dir)
    testers_schema_path = File.join(Rails.configuration.x.autotest.client_dir, 'testers.json')

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
    create_submission
    process_schema_data
  end

  def create_new_assignment
    puts "Creating sample autotesting assignment #{@assg_short_id}"
    Assignment.create(
      short_identifier: @assg_short_id,
      description: 'Assignment for testing the autotester',
      message: '',
      due_date: 1.week.from_now,
      is_hidden: false,
      assignment_properties_attributes: {
        group_name_autogenerated: false,
        repository_folder: @assg_short_id,
        enable_test: true,
        token_start_date: Time.current,
        token_period: 1,
        enable_student_tests: true,
        unlimited_tokens: true
      },
    )
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
      assessment_id: @assignment.id,
      weight: 1,
    )
    marking_scheme.marking_weights << marking_weight
  end

  def create_criteria
    FlexibleCriterion.find_or_create_by(
      name: 'criterion',
      assessment_id: @assignment.id,
      position: 1,
      max_mark: 5,
      assigned_groups_count: nil
    )
  end

  def create_submission
    student = Student.find_by(user_name: 'aaaautotest')
    student.create_group_for_working_alone_student(@assignment.id)
    group = Group.find_by group_name: student.user_name
    grouping = Grouping.find_by(group_id: group, assessment_id: @assignment.id)
    grouping.access_repo do |repo|
      transaction = repo.get_transaction(student.user_name)
      @student_files.each do |file_path|
        File.open(file_path, 'r') do |file|
          file_rel_path = Pathname.new(file_path).relative_path_from Pathname.new(@student_dir)
          repo_path = File.join(@assignment.repository_folder, file_rel_path)
          transaction.add(repo_path, file.read, '')
        end
      end
      repo.commit(transaction)
    end
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
    end
  end
end
