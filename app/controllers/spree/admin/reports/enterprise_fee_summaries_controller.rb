require "open_food_network/reports"
require "order_management/reports/enterprise_fee_summary/parameters"
require "order_management/reports/enterprise_fee_summary/permissions"
require "order_management/reports/enterprise_fee_summary/authorizer"
require "order_management/reports/enterprise_fee_summary/report_service"
require "order_management/reports/enterprise_fee_summary/renderers/csv_renderer"
require "order_management/reports/enterprise_fee_summary/renderers/html_renderer"

module Spree
  module Admin
    module Reports
      class EnterpriseFeeSummariesController < BaseController
        before_filter :load_report_parameters
        before_filter :load_permissions

        def new; end

        def create
          return respond_to_invalid_parameters unless @report_parameters.valid?

          @authorizer = report_klass::Authorizer.new(@report_parameters, @permissions)
          @authorizer.authorize!
          @report = report_klass::ReportService.new(@permissions, @report_parameters)
          renderer.render(self)
        rescue OpenFoodNetwork::Reports::Authorizer::ParameterNotAllowedError => e
          flash[:error] = e.message
          render_report_form
        end

        private

        def respond_to_invalid_parameters
          flash[:error] = I18n.t("invalid_filter_parameters", scope: i18n_scope)
          render_report_form
        end

        def i18n_scope
          "order_management.reports.enterprise_fee_summary"
        end

        def render_report_form
          render action: :new
        end

        def report_klass
          OrderManagement::Reports::EnterpriseFeeSummary
        end

        def load_report_parameters
          @report_parameters = report_klass::Parameters.new(params[:report] || {})
        end

        def load_permissions
          @permissions = report_klass::Permissions.new(spree_current_user)
        end

        def report_renderer_klass
          case params[:report_format]
          when "csv"
            report_klass::Renderers::CsvRenderer
          when nil, "", "html"
            report_klass::Renderers::HtmlRenderer
          else
            raise OpenFoodNetwork::Reports::UnsupportedReportFormatException
          end
        end

        def renderer
          @renderer ||= report_renderer_klass.new(@report)
        end
      end
    end
  end
end