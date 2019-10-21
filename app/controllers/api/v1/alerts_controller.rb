

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
          sizes = gateway.position_sizes()
          if sizes[:buy] == 0
            if sizes[:sell] > 0
              gateway.close_all()
            end
            gateway.buy()
          end
        when 'short'
          sizes = gateway.position_sizes()
          if sizes[:sell] == 0
            if sizes[:buy] > 0
              gateway.close_all()
            end
            gateway.sell()
          end
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
          @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY', size: 0.01)
        end

        def sell()
          @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: 0.01)
        end

        def close_all()
          sizes = position_sizes()
          if sizes[:buy] > 0
            @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: sizes[:buy])
          elsif sizes[:sell] > 0
            @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY',  size: sizes[:sell])
          end
        end

        def positions()
          @private_client.positions(product_code: 'FX_BTC_JPY')
        end

        def position_sizes()
          result = positions()

          buy = 0
          sell = 0
          result.each do |position|
            side = position['side']
            if side == 'BUY'
              buy += position['size']
            elsif side == 'SELL'
              sell += position['size']
            end
          end
          {buy: buy, sell: sell}
        end
      end
    end
  end
end
