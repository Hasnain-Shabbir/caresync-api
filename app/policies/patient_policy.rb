class PatientPolicy < ApplicationPolicy
  def index? = true
  def show? = true

  def create? = user.admin? || user.provider? || user.front_desk?
  def update? = user.admin? || user.provider? || user.nurse?
  def destroy? = user.admin?

  def view_date_of_birth? = !user.front_desk?
end
