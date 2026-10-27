# frozen_string_literal: true

module Types
  class PatientPageType < Types::BaseObject
    field :patients, [ Types::PatientType ], null: false, hash_key: :nodes
    # Metadata costs the same for 1 row or 100, so it is free. Only `patients` is multiplied by per_page.
    field :total_count, Integer, null: false, complexity: 0, description: "Rows across all pages"
    field :total_pages, Integer, null: false, complexity: 0
    field :page, Integer, null: false, complexity: 0
    field :per_page, Integer, null: false, complexity: 0
    field :has_next_page, Boolean, null: false, complexity: 0
    field :has_previous_page, Boolean, null: false, complexity: 0
  end
end
