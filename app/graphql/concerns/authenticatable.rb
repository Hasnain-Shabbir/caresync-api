module Authenticatable
  def current_user
    context[:current_user]
  end

  def current_user!
    current_user || raise(GraphQL::ExecutionError.new("Authentication required", extensions: { code: "UNAUTHENTICATED" }))
  end

  def current_organization
    current_user!.organization
  end
end
