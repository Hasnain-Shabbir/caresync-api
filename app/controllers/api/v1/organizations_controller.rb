module Api
  module V1
    class OrganizationsController < ApplicationController
      def index
        organizations = Organization.order(:name)
        render json: organizations
      end
    end
  end
end
