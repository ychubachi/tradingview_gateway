

module Api
  module V1
    class AlertsController < ApplicationController
      before_action :set_alert, only: [:show, :update, :destroy]

      def index
        alerts = Alert.order(created_at: :desc)
        render json: { status: 'SUCCESS', message: 'Loaded alerts', data: alerts }
      end

      def show
        render json: { status: 'SUCCESS', message: 'Loaded the alert', data: @alert }
      end

      def create
        puts "##################"
        puts params
        alert = Alert.new(alert_params)
        if alert.save
          render json: { status: 'SUCCESS', data: alert }
        else
          render json: { status: 'ERROR', data: alert.errors }
        end

        key = ENV['KEY']
        secret = ENV['SECRET']
        gateway = BitflyerGateway.new(key, secret)

        case alert.strategy
        when 'long'
          gateway.close_all()
          gateway.buy()
        when 'short'
          gateway.close_all()
          gateway.sell()
        when 'close_all'
          gateway.close_all()
        end

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
        params.require(:alert).permit(:tickerid, :strategy)
      end

      class BitflyerGateway
        def initialize(key, secret)
          @key = key
          @secret = secret
          @private_client = Bitflyer.http_private_client(key, secret)
        end

        def buy()
          # close_all()
          @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01)
        end

        def sell()
          # close_all()
          @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: 0.01)
        end

        def close_all()
          size_buy = 0
          size_sell = 0

          result = positions()
          result.each do |position|
            side = position['side']
            if side == 'BUY'
              size_buy += position['size']
            elsif side == 'SELL'
              size_sell += position['size']
            end
          end

          if size_buy > 0
            @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: size_buy)
          elsif size_sell > 0
            @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY',  size: size_sell)
          end

          positions()
        end

        def positions()
          @private_client.positions(product_code: 'FX_BTC_JPY')
        end
      end
    end
  end
end
