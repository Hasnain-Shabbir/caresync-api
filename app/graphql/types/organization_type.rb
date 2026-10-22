module Types
  class OrganizationType < Types::BaseObject
    field :id, ID, null: false
    field :name, String, null: false
    field :patients, [ Types::PatientType ], null: false, complexity: Types::BaseField::LIST_COMPLEXITY

    def patients
      dataloader.with(GraphQL::Dataloader::ActiveRecordAssociationSource, :patients).load(object)
    end
  end
end
