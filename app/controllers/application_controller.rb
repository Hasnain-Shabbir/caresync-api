class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :render_unprocessable
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from ActiveRecord::DeleteRestrictionError, with: :render_conflict

  private
  def render_not_found(exception)
    render json: {
      error: {
        code: "not_found",
        message: "#{exception.model || 'Record'} not found"
      }
    }, status: :not_found
  end

  private
  def render_unprocessable(exception)
    render json: {
      error: {
        code: "validation_failed",
        message: "Validation failed",
        details: exception.record.errors.to_hash
      }
    }, status: :unprocessable_content
  end

  private
  def render_bad_request(exception)
    render json: {
      error: {
        code: "bad_request",
        message: "Missing parameter: #{exception.param}"
      }
    }, status: :bad_request
  end

  def render_conflict(exception)
    render json: {
      error: {
        code: "conflict",
        message: "Cannot delete this record because other records depend on it"
      }
    }, status: :conflict
  end
end
