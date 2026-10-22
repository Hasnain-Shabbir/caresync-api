module Organizations
  class Update
    def self.call(...) = new(...).call

    def initialize(organization:, attributes:)
      @organization = organization
      @attributes = attributes
    end

    def call
      if @organization.update(@attributes)
        Result.success(@organization)
      else
        Result.failure("VALIDATION_FAILED", "Organization is invalid", @organization)
      end
    end
  end
end
