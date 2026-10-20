# frozen_string_literal: true

module Types
  class MutationType < Types::BaseObject
    field :create_organization, mutation: Mutations::CreateOrganization
    field :update_organization, mutation: Mutations::UpdateOrganization
    field :delete_organization, mutation: Mutations::DeleteOrganization
  end
end
