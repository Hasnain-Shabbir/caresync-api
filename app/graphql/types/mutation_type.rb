# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :update_organization, mutation: Mutations::UpdateOrganization

    field :create_patient, mutation: Mutations::CreatePatient
    field :update_patient, mutation: Mutations::UpdatePatient
    field :delete_patient, mutation: Mutations::DeletePatient

    field :login, mutation: Mutations::Login
    field :logout, mutation: Mutations::Logout
  end
end
