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

  def authorize!(record, query)
    return true if Pundit.policy!(current_user!, record).public_send(query)
    raise GraphQL::ExecutionError.new("You are not allowed to do that", extensions: { code: "FORBIDDEN" })
  end
end
