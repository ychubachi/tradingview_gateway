require 'bitflyer_gateway'

module Api
  module V1
    class AlertsController < ApplicationController
      before_action :set_alert, only: [:show, :update, :destroy]

      def index
        TradeJob.perform_later(nil)

        alerts = Alert.order(created_at: :desc)
        render json: { status: 'SUCCESS', message: 'Loaded alerts', data: alerts }
      end

      def show
        render json: { status: 'SUCCESS', message: 'Loaded the alert', data: @alert }
      end

      def create
        alert = Alert.new(alert_params)

        key = params['key']
        secret = JSON.parse(ENV["API_SECRET"])["BITFLYER"]
        gateway = BitflyerGateway.new(key, secret)

        parameters = {
            size: alert.qty,
            profit: alert.profit, loss: alert.loss, risk: alert.risk
        }.delete_if { |_, v| v.nil? }
        case alert.trade
        when 'long'
          gateway.long(parameters)
        when 'short'
          gateway.short(parameters)
        when 'close_all'
          gateway.close_all
        end

        # if alert.save
          render json: { status: 'SUCCESS', data: alert }
        # else
        #   render json: { status: 'ERROR', data: alert.errors }
        # end
      end

      def destroy
        @alert.destroy
        render json: { status: 'SUCCESS', message: 'Deleted the alert', data: @alert }
      end

      def update
        if @alert.update(alert_params)
          render json: { status: 'SUCCESS', message: 'Updated the alert', data: @alert }
        else
          render json: { status: 'SUCCESS', message: 'Not updated', data: @alert.errors }
        end
      end

      private

      def set_alert
        @alert = Alert.find(params[:id])
      end

      def alert_params
        params.require(:alert).permit(:trade, :qty, :profit, :loss, :risk,
          :exchange, :ticker)
      end
    end
  end
end
