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

    paginated_field :patients, Types::PatientPageType do
      argument :order_by, Types::PatientOrderEnum, required: true, default_value: { last_name: :asc, first_name: :asc }
    end

    def patients(page:, per_page:, order_by:)
      authorize!(Patient, :index?)
      scope = current_organization.patients.order(order_by).order(:id)
      Paginator.call(scope, page: page, per_page: per_page)
    end

    def patient(id:)
      record = current_organization.patients.find(id)
      authorize!(record, :show?)
      record
    end
  end
end
