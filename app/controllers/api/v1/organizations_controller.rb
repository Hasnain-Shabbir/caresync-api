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
        render json: "Create route is working"
      end

      def update
        render json: "Update route is working"
      end

      def destroy
        render json: "Destroy route is working"
      end

    end
  end
end
