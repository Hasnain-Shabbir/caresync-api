# frozen_string_literal: true

module Types
  class PatientOrderEnum < Types::BaseEnum
    description "Allowed sort orders for the patients list"

    value "LAST_NAME_ASC", value: { last_name: :asc, first_name: :asc }
    value "LAST_NAME_DESC", value: { last_name: :desc, first_name: :desc }
    value "CREATED_AT_ASC", value: { created_at: :asc }
    value "CREATED_AT_DESC", value: { created_at: :desc }
  end
end
