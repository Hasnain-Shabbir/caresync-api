# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_organization, mutation: Mutations::CreateOrganization
    field :update_organization, mutation: Mutations::UpdateOrganization
    field :delete_organization, mutation: Mutations::DeleteOrganization

    field :create_patient, mutation: Mutations::CreatePatient
    field :update_patient, mutation: Mutations::UpdatePatient
    field :delete_patient, mutation: Mutations::DeletePatient
  end
end
