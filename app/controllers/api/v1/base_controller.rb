# frozen_string_literal: true

module Api
  module V1
    # Base controller for API v1 endpoints
    # Provides common error handling and response helpers
    class BaseController < ApplicationController
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ActionController::ParameterMissing, with: :bad_request

      private

      def not_found(exception)
        render json: { error: exception.message }, status: :not_found
      end

      def bad_request(exception)
        render json: { error: exception.message }, status: :bad_request
      end

      # Pagination helper
      def paginate(collection)
        page = (params[:page] || 1).to_i
        per_page = [ (params[:per_page] || 25).to_i, 100 ].min

        total = collection.count
        records = collection.offset((page - 1) * per_page).limit(per_page)

        {
          data: records,
          meta: {
            page: page,
            per_page: per_page,
            total: total,
            total_pages: (total.to_f / per_page).ceil
          }
        }
      end
    end
  end
end
