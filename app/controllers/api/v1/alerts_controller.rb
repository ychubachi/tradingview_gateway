require 'bitflyer'

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

        key = params['key']
        secret = ENV['SECRET']
        gateway = BitflyerGateway.new(key, secret)

        case alert.strategy
        when 'long'
          gateway.buy
        when 'short'
          gateway.sell
        when 'close_all'
          gateway.close_all
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
        params.require(:alert).permit(:strategy)
      end
    end
  end
end

class BitflyerGateway
  def initialize(key, secret)
    @key = key
    @secret = secret
    @public_client = Bitflyer.http_public_client # (key, secret)
    @private_client = Bitflyer.http_private_client(key, secret)
  end

  def buy(limit_stop = 10000.0, risk_parcentage = 0.02)
    ps = position_sizes
    if ps[:buy] > 0 # No pyramiding
      return
    end

    if ps[:sell] > 0
      close_all
    end

    size = calculate_size(limit_stop, risk_parcentage)
    tp = trigger_price(-limit_stop)
    parameters = [{
      "product_code": "FX_BTC_JPY",
      "condition_type": "MARKET",
      "side": "BUY",
      "size": size
    },
    {
      "product_code": "FX_BTC_JPY",
      "condition_type": "STOP",
      "side": "SELL",
      "trigger_price": tp,
      "size": size
    }]

    @private_client.send_parent_order(order_method: 'IFD', parameters: parameters)
  end

  def sell(limit_stop = 10000.0, risk_parcentage = 0.02)
    ps = position_sizes
    if ps[:sell] > 0 # No pyramiding
      return
    end

    if ps[:buy] > 0
      close_all
    end

    size = calculate_size(limit_stop, risk_parcentage)
    tp = trigger_price(limit_stop)
    parameters = [{
      "product_code": "FX_BTC_JPY",
      "condition_type": "MARKET",
      "side": "SELL",
      "size": size
    },
    {
      "product_code": "FX_BTC_JPY",
      "condition_type": "STOP",
      "side": "BUY",
      "trigger_price": tp,
      "size": size
    }]
    @private_client.send_parent_order(order_method: 'IFD', parameters: parameters)
  end

  def close_all
    sizes = position_sizes
    if sizes[:buy] > 0
      @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'SELL', size: sizes[:buy])
    elsif sizes[:sell] > 0
      @private_client.send_child_order(product_code: 'FX_BTC_JPY', child_order_type: 'MARKET', side: 'BUY',  size: sizes[:sell])
    end
    @private_client.cancel_all_child_orders(product_code: 'FX_BTC_JPY')
  end

  def position_sizes
    positions = @private_client.positions(product_code: 'FX_BTC_JPY')

    buy = 0
    sell = 0
    positions.each do |position|
      side = position['side']
      if side == 'BUY'
        buy += position['size']
      elsif side == 'SELL'
        sell += position['size']
      end
    end
    {buy: buy, sell: sell}
  end

  def calculate_size(limit_stop = 10000.0, risk_parcentage = 0.02)
    collateral = @private_client.collateral['collateral'] # 預入証拠金
    amount_at_risk = (collateral * risk_parcentage).floor # 許容損失額（リスク）
    (amount_at_risk / limit_stop).round(2)                # 売買するサイズ
  end

  def trigger_price(limit_stop = 10000.0)
    mid_price = @public_client.board(product_code: 'FX_BTC_JPY')['mid_price']
    mid_price + limit_stop
  end
end