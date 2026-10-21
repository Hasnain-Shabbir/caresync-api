class OrganizationPolicy < ApplicationPolicy
  def show? = true
  def update? = user.admin?
end
