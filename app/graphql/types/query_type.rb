# frozen_string_literal: true

module Types
  class QueryType < Types::BaseObject
    field :organizations, [ Types::OrganizationType ], null: false

    def organizations
      current_user!
      Organization.where(id: current_organization.id).order(:name)
    end

    field :organization, Types::OrganizationType, null: true do
      argument :id, ID, required: true
    end

    def organization(id:)
      current_user!
      Organization.where(id: current_organization.id).find(id)
    end

    field :patient, Types::PatientType, null: true do
      argument :id, ID, required: true
    end

    field :patients, [ Types::PatientType ], null: false

    def patients
      authorize!(Patient, :index?)
      current_organization.patients.order(:last_name, :first_name)
    end

    def patient(id:)
      record = current_organization.patients.find(id)
      authorize!(record, :show?)
      record
    end
  end
end
