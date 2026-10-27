module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :patients_count, Integer, null: false, description: "Number of patients. Use Query.patients for the list."

    paginated_field :patients, Types::PatientPageType, description: "One page of the organization's patients" do
      argument :order_by, Types::PatientOrderEnum, required: true, default_value: { last_name: :asc, first_name: :asc }
    end

    def patients(page:, per_page:, order_by:)
      authorize!(Patient, :index?)
      Paginator.call(object.patients.order(order_by).order(:id), page: page, per_page: per_page)
    end

    # A cheap count, for pages that only need the number: bounded, and it keeps the schema free of an organization -> patients -> organization cycle.
    def patients_count
      authorize!(Patient, :index?)
      object.patients.count
    end
  end
end
