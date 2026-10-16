module Api
  module V1
    class OrganizationsController < ApplicationController
      before_action :set_organization, only: [:show, :update, :destroy]

      def index
        organizations = Organization.order(:name)
        render json: organizations
      end

      def show
        render json: @organization
      end

      def create
        organization = Organization.create!(organization_params)
        render json: organization, status: :created
      end

      def update
        @organization.update!(organization_params)
        render json: @organization
      end

      def destroy
        @organization.destroy!
        head :no_content
      end


      private
      def set_organization
        @organization = Organization.find(params[:id])
      end
      
      # Define params body
      def organization_params
        params.expect(organization: [:name])
      end

    end
  end
end
