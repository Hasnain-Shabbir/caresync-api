class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

  private
  def render_not_found(exception)
    render json: {
      error: {
        code: "not_found",
        message: "#{exception.model || 'Record'} not found"
      }
    }, status: :not_found
  end
end
