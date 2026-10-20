# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :organizations, [ Types::OrganizationType ], null: false

    def organizations
      Organization.order(:name)
    end

    field :organization, Types::OrganizationType, null: true do
      argument :id, ID, required: true
    end

    def organization(id:)
      Organization.find(id)
    end

    field :patient, Types::PatientType, null: true do
      argument :id, ID, required: true
    end

    def patient(id:)
      Patient.find(id)
    end
  end
end
