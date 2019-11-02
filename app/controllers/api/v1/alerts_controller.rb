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
        secret = JSON.parse(ENV["API_SECRET"])["BITFLYER"]
        gateway = BitflyerGateway.new(key, secret)

        case alert.strategy
        when 'long'
          gateway.long
        when 'short'
          gateway.short
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

require 'bitflyer'

class BitflyerGateway
  def initialize(key, secret)
    puts "#{__method__}: ENTER"
    @key = key
    @secret = secret
    @public_client  = Bitflyer.http_public_client
    @private_client = Bitflyer.http_private_client(key, secret)
    puts "#{__method__}: EXIT"
  end

  def long(profit = 1000.0, loss = 500.0, risk = 0.02)
    puts "#{__method__}: ENTER"
    puts "#{__method__}: profit = #{profit}, loss = #{loss}, risk = #{risk})"
    ps = position_sizes
    puts "#{__method__}: position_sizes = #{ps}"
    if ps[:buy] > 0
      puts "#{__method__}: EXIT(no pyramiding)"
      return
    end
    if ps[:sell] > 0
      close_all
    end
    order('BUY', risk, loss, profit)
    puts "#{__method__}: EXIT"
  end

  def short(profit = 1000.0, loss = 500.0, risk = 0.02)
    puts "#{__method__}: ENTER"
    puts "#{__method__}: profit = #{profit}, loss = #{loss}, risk = #{risk})"
    ps = position_sizes
    puts "#{__method__}: position_sizes = #{ps}"
    if ps[:sell] > 0
      puts "#{__method__}: EXIT(no pyramiding)"
      return
    end
    if ps[:buy] > 0
      close_all
    end
    order('SELL', risk, loss, profit)
    puts "#{__method__}: EXIT"
  end

  def close_all
    puts "#{__method__}: ENTER"
    puts "#{__method__}: CALL: cancel_all_child_orders"
    r = @private_client.cancel_all_child_orders(product_code: 'FX_BTC_JPY')
    puts "#{__method__}: r = #{r}"
    sizes = position_sizes
    puts "#{__method__}: sizes = #{sizes}"

    try = 0
    begin
      try += 1
      if sizes[:buy] > 0
        puts "#{__method__}: CALL: send_child_order"
        r =  @private_client.send_child_order(product_code: 'FX_BTC_JPY',
          child_order_type: 'MARKET', side: 'SELL', size: sizes[:buy])
        if r['status'] != nil
          raise r.to_s # 発注失敗
        end
        puts "#{__method__}: r = #{r}"
      elsif sizes[:sell] > 0
        puts "#{__method__}: CALL: send_child_order"
        r = @private_client.send_child_order(product_code: 'FX_BTC_JPY',
          child_order_type: 'MARKET', side: 'BUY',  size: sizes[:sell])
        if r['status'] != nil
          raise r.to_s # 発注失敗
        end
        puts "#{__method__}: r = #{r}"
      end
    rescue
      sleep(0.1)
      retry if try < 10
      raise 'close_all failed'
    end
    puts "#{__method__}: EXIT"
  end

  def position_sizes
    puts "#{__method__}: ENTER"
    positions = @private_client.positions(product_code: 'FX_BTC_JPY')
    buy  = 0.0
    sell = 0.0
    positions.each do |position|
      side = position['side']
      if side == 'BUY'
        buy += position['size']
      elsif side == 'SELL'
        sell += position['size']
      end
    end
    buy  = buy.round(2) # ex) 0.045 + 0.005 = 0.049999999999999996
    sell = sell.round(2)
    puts "#{__method__}: EXIT"
    {buy: buy, sell: sell}
  end

  def order(side,
      risk_parcentage = 0.02, loss_price = 1000.0,
      profit_price = 1000.0)
    puts "#{__method__}: ENTER"
    puts "#{__method__}: side = #{side}, risk_parcentage = #{risk_parcentage}" +
      ", loss_price = #{loss_price}, profit_price = #{profit_price}"

    # ==========================================================================
    # 現在の値段を取得する
    # --------------------------------------------------------------------------
    current_price = @public_client.board(
        product_code: 'FX_BTC_JPY')['mid_price']
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 許容リスクに基づき取引量を計算する
    # --------------------------------------------------------------------------
    # 取引量は、価格が仮に現在値よりも loss_price 下がった場合でも、
    # 預入証拠金の risk_parcentage までの損失に抑える量にする
    # --------------------------------------------------------------------------
    collateral = @private_client.collateral['collateral'] # 預入証拠金
    amount_at_risk = (collateral * risk_parcentage).floor # 許容損失額（リスク）
    size = (amount_at_risk / loss_price).round(2)         # 売買するサイズ
    if (size * current_price) * 1.01 > collateral * 4     # 購入できるか？
      size = ((collateral * 4) / current_price).round(2)  # 購入できる取引量に
      size = (size * 100 - 1) / 100                       # 誤差修正
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 決済注文を発注する
    # --------------------------------------------------------------------------
    case side
    when 'BUY'
      oposite_side = 'SELL'
      limit_price = current_price + profit_price
      stop_price  = current_price - loss_price
    when 'SELL'
      oposite_side = 'BUY'
      limit_price = current_price - profit_price
      stop_price  = current_price + loss_price
    end

    parameters = [{
      "product_code": "FX_BTC_JPY",
      "condition_type": "MARKET",
      "side": side,
      "size": size
    },
    {
      "product_code": "FX_BTC_JPY",
      "condition_type": "LIMIT",
      "side": oposite_side,
      "price": limit_price,
      "size": size
    },
    {
      "product_code": "FX_BTC_JPY",
      "condition_type": "STOP",
      "side": oposite_side,
      "trigger_price": stop_price,
      "size": size
    }]

    puts "#{__method__}: CALL send_parent_order"
    puts "#{__method__}: parameters = #{parameters}"
    r = @private_client.send_parent_order(
        order_method: 'IFDOCO', parameters: parameters)
    if r['status'] != nil
      raise r.to_s # 発注失敗
    end
    puts "#{__method__}: r = #{r}"
    puts "#{__method__}: EXIT"
  end
end
