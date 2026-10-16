module Api
  module V1
    class OrganizationsController < ApplicationController
      def index
        organizations = Organization.order(:name)
        render json: organizations
      end

      def show
        org = Organization.find(params[:id])
        render json: org
      end

      def create
        organization = Organization.create!(organization_params)
        render json: organization, status: :created
      end

      def update
        render json: "Update route is working"
      end

      def destroy
        render json: "Destroy route is working"
      end

      # Define params body
      private
      def organization_params
        params.expect(organization: [:name])
      end

    end
  end
end
