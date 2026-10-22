# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :update_organization, mutation: Mutations::Organizations::UpdateOrganization

    field :create_patient, mutation: Mutations::Patients::CreatePatient
    field :update_patient, mutation: Mutations::Patients::UpdatePatient
    field :delete_patient, mutation: Mutations::Patients::DeletePatient

    field :login, mutation: Mutations::Auth::Login
    field :logout, mutation: Mutations::Auth::Logout

    field :request_password_reset, mutation: Mutations::Auth::RequestPasswordReset
    field :reset_password, mutation: Mutations::Auth::ResetPassword
  end
end
