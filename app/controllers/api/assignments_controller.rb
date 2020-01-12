module Api

  # Allows for adding, modifying and showing Markus assignments.
  # Uses Rails' RESTful routes (check 'rake routes' for the configured routes)
  class AssignmentsController < MainApiController
    # Define default fields to display for index and show methods
    DEFAULT_FIELDS = [:id, :description, :short_identifier, :message, :due_date,
                      :group_min, :group_max, :tokens_per_period, :allow_web_submits,
                      :student_form_groups, :remark_due_date, :remark_message,
                      :assign_graders_to_criteria, :enable_test, :enable_student_tests, :allow_remarks,
                      :display_grader_names_to_students, :group_name_autogenerated,
                      :repository_folder, :is_hidden, :vcs_submit, :token_period,
                      :non_regenerating_tokens, :unlimited_tokens, :token_start_date, :has_peer_review].freeze

    # Returns a list of assignments and their attributes
    # Optional: filter, fields
    def index
      assignments = get_collection(Assignment) || return

      respond_to do |format|
        format.xml { render xml: assignments.to_xml(only: DEFAULT_FIELDS, root: 'assignments', skip_types: 'true') }
        format.json { render json: assignments.to_json(only: DEFAULT_FIELDS) }
      end
    end

    # Returns an assignment and its attributes
    # Requires: id
    # Optional: filter, fields
    def show
      assignment = Assignment.find_by_id(params[:id])
      if assignment.nil?
        # No assignment with that id
        render 'shared/http_status', locals: {code: '404', message:
          'No assignment exists with that id'}, status: 404
      else
        respond_to do |format|
          format.xml { render xml: assignment.to_xml }
          format.json { render json: assignment.to_json }
        end
      end
    end

    # Creates a new assignment
    # Requires: short_identifier, due_date, description
    # Optional: repository_folder, group_min, group_max, tokens_per_period,
    # submission_rule_type, allow_web_submits,
    # display_grader_names_to_students, enable_test, assign_graders_to_criteria,
    # message, allow_remarks, remark_due_date, remark_message, student_form_groups,
    # group_name_autogenerated, submission_rule_deduction, submission_rule_hours,
    # submission_rule_interval
    def create
      if has_missing_params?([:short_identifier, :due_date, :description])
        # incomplete/invalid HTTP params
        render 'shared/http_status', locals: {code: '422', message:
          HttpStatusHelper::ERROR_CODE['message']['422']}, status: 422
        return
      end

      # check if there is an existing assignment
      assignment = Assignment.find_by_short_identifier(params[:short_identifier])
      unless assignment.nil?
        render 'shared/http_status', locals: {code: '409', message:
          'Assignment already exists'}, status: 409
        return
      end

      # No assignment found so create new one
      attributes = { short_identifier: params[:short_identifier] }
      attributes = process_attributes(params, attributes)

      new_assignment = Assignment.new(attributes)
      new_assignment.build_assignment_stat

      # Get and assign the submission_rule
      submission_rule = get_submission_rule(params)

      if submission_rule.nil?
        render 'shared/http_status', locals: {code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500']}, status: 500
        return
      end

      new_assignment.submission_rule = submission_rule

      unless new_assignment.save
        # Some error occurred
        render 'shared/http_status', locals: {code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500']}, status: 500
        return
      end

      # Otherwise everything went alright.
      render 'shared/http_status', locals: {code: '201', message:
        HttpStatusHelper::ERROR_CODE['message']['201']}, status: 201
    end

    # Updates an existing assignment
    # Requires: id
    # Optional: short_identifier, due_date,repository_folder, group_min, group_max,
    # tokens_per_period, submission_rule_type, allow_web_submits,
    # display_grader_names_to_students, enable_test, assign_graders_to_criteria,
    # description, message, allow_remarks, remark_due_date, remark_message,
    # student_form_groups, group_name_autogenerated, submission_rule_deduction,
    # submission_rule_hours, submission_rule_interval
    def update
      # If no assignment is found, render an error.
      assignment = Assignment.find_by_id(params[:id])
      if assignment.nil?
        render 'shared/http_status', locals: {code: '404', message:
          'Assignment was not found'}, status: 404
        return
      end

      # Create a hash to hold fields/values to be updated for the assignment
      attributes = {}

      unless params[:short_identifier].blank?
        # Make sure another assignment isn't using the new short_identifier
        other_assignment = Assignment.find_by_short_identifier(
          params[:short_identifier])
        if !other_assignment.nil? && other_assignment != assignment
          render 'shared/http_status', locals: {code: '409', message:
            'short_identifier already in use'}, status: 409
          return
        end
        attributes[:short_identifier] = params[:short_identifier]
      end

      attributes = process_attributes(params, attributes)
      assignment.attributes = attributes

      # Update the submission rule if provided
      unless params[:submission_rule_type].nil?
        submission_rule = get_submission_rule(params)
        if submission_rule.nil?
          render 'shared/http_status', locals: {code: '500', message:
            HttpStatusHelper::ERROR_CODE['message']['500']}, status: 500
          return
        else
          # If it's a valid submission rule, replace the existing one
          if submission_rule.valid?
            assignment.submission_rule.destroy
            assignment.submission_rule = submission_rule
          end
        end
      end

      unless assignment.save
        # Some error occurred
        render 'shared/http_status', locals: {code: '500', message:
          HttpStatusHelper::ERROR_CODE['message']['500']}, status: 500
        return
      end

      # Made it this far, render success
      render 'shared/http_status', locals: {code: '200', message:
        HttpStatusHelper::ERROR_CODE['message']['200']}, status: 200
    end

    # Process the parameters passed for assignment creation and update
    def process_attributes(params, attributes)
      # Loop through default fields other than id
      fields = Array.new(DEFAULT_FIELDS)
      fields.delete(:id)
      fields.each do |field|
        attributes[field] = params[field] if !params[field].nil?
      end

      # Some attributes have to be set with default values when creating a new
      # assignment. They're based on the view's defaults.
      if request.post?
        attributes[:assignment_properties_attributes] = {}
        params[:assignment_properties_attributes] = {} if params[:assignment_properties_attributes].nil?
        if params[:assignment_properties_attributes][:repository_folder].nil?
          attributes[:assignment_properties_attributes][:repository_folder] = attributes[:short_identifier]
        end
        attributes[:is_hidden] = 0 if params[:is_hidden].nil?
      end

      attributes
    end

    # Gets the submission rule for POST/PUT requests based on the supplied params
    # Defaults to NoLateSubmissionRule
    def get_submission_rule(params)
      if params[:submission_rule_type] == 'GracePeriod'
        submission_rule = GracePeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours])
        submission_rule.periods << period

      elsif params[:submission_rule_type] == 'PenaltyDecayPeriod'
        submission_rule = PenaltyDecayPeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours],
                            deduction: params[:submission_rule_deduction],
                            interval: params[:submission_rule_interval])
        submission_rule.periods << period

      elsif params[:submission_rule_type] == 'PenaltyPeriod'
        submission_rule = PenaltyPeriodSubmissionRule.new
        period = Period.new(hours: params[:submission_rule_hours],
                            deduction: params[:submission_rule_deduction])
        submission_rule.periods << period

      else
        submission_rule = NoLateSubmissionRule.new
      end

      submission_rule
    end

    def grades_summary
      assignment = Assignment.find(params[:id])
      send_data assignment.summary_csv(@current_user),
                type: 'text/csv',
                filename: "#{assignment.short_identifier}_grades_summary.csv",
                disposition: 'inline'
    rescue ActiveRecord::RecordNotFound => e
      render 'shared/http_status', locals: { code: '404', message: e }, status: 404
    end
  end # end AssignmentsController
end
