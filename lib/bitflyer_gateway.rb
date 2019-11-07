require 'bitflyer'

module Retriable
  def with_retry(max_attempts: 5)
    # puts "#{__method__}: ENTER"
    attempts = 0
    begin
      attempts += 1
      yield
    rescue RetryError => e
      puts "#{__method__}: retry #{attempts}/#{max_attempts}"
      raise e.cause if max_attempts < attempts
      retry
    end
    # puts "#{__method__}: EXIT"
  end
end

class BitflyerGateway
  include Retriable

  def initialize(key, secret)
    # puts "#{__method__}: ENTER"
    @key = key
    @secret = secret
    @public_client  = Bitflyer.http_public_client
    @private_client = Bitflyer.http_private_client(key, secret)
    # puts "#{__method__}: EXIT"
  end

  def long(size: nil, profit: 1000.0, loss: 500.0, risk: 0.02)
    puts "#{__method__}: ENTER(size = #{size}, profit = #{profit}, loss = #{loss}, risk = #{risk})"
    ps = position_sizes
    puts "#{__method__}: position_sizes = #{ps}"
    if ps[:buy] > 0
      puts "#{__method__}: EXIT(no pyramiding)"
      return
    end
    if ps[:sell] > 0
      close_all
    end
    order(side: 'BUY', size: size, profit: profit, loss: loss, risk: risk)
    puts "#{__method__}: EXIT"
  end

  def short(size: nil, profit: 1000.0, loss: 500.0, risk: 0.02)
    puts "#{__method__}: ENTER(size = #{size}, profit = #{profit}, loss = #{loss}, risk = #{risk})"
    ps = position_sizes
    puts "#{__method__}: position_sizes = #{ps}"
    if ps[:sell] > 0
      puts "#{__method__}: EXIT(no pyramiding)"
      return
    end
    if ps[:buy] > 0
      close_all
    end
    order(side: 'SELL', size: size, profit: profit, loss: loss, risk: risk)
    puts "#{__method__}: EXIT"
  end

  def close_all
    puts "#{__method__}: ENTER()"
    # ==========================================================================
    # 今ある全注文を取り消す
    # --------------------------------------------------------------------------
    cancel_all_child_orders
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 今ある建玉のサイズを取得する
    # --------------------------------------------------------------------------
    sizes = position_sizes
    puts "#{__method__}: sizes = #{sizes}"
    # --------------------------------------------------------------------------

    if sizes[:buy] > 0
      send_child_order(side: 'SELL', size: sizes[:buy])
    elsif sizes[:sell] > 0
      send_child_order(side: 'BUY', size: sizes[:sell])
    end
    puts "#{__method__}: EXIT"
  end

private
  def position_sizes
    # puts "#{__method__}: ENTER"
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
    # puts "#{__method__}: EXIT"
    {buy: buy, sell: sell}
  end

  def position_price
    # puts "#{__method__}: ENTER"

    try = 0
    begin
      positions = @private_client.positions(product_code: 'FX_BTC_JPY')
      if positions.size == 0
        raise
      end
    rescue
      try += 1
      if try < 10
        sleep(0.1)
        puts "#{__method__}: waiting for positions.. #{try}/10"
        retry
      end
      raise "#{__method__}: timeout"
    end

    price = 0.0
    size = 0.0
    positions.each do |position|
      size += position['size']
      price += position['price'] * position['size']
    end
    avg_price = (price / size).floor
    puts "#{__method__}: avg price=#{avg_price}"
    # puts "#{__method__}: EXIT"
    avg_price
  end

  def order(side: nil, size: nil, profit: 1000.0, loss: 1000.0, risk: 0.02)
    puts "#{__method__}: ENTER(side = #{side}, size = #{size}, " +
      "profit = #{profit}, loss = #{loss}, risk = #{risk})"

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
    if size == nil
      size = size_at_risk(current_price: current_price, loss: loss, risk: risk)
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 注文を発注する
    # --------------------------------------------------------------------------
    send_child_order(side: side, size: size)
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 建玉から平均取得単価を求める
    # --------------------------------------------------------------------------
    begin
      current_price = average_price
    rescue
      puts 'could not get average price of current positions. use mid price.'
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 利確・損切の価格を計算する
    # --------------------------------------------------------------------------
    case side
    when 'BUY'
      oposite_side = 'SELL'
      limit = current_price + profit
      stop  = current_price - loss
    when 'SELL'
      oposite_side = 'BUY'
      limit = current_price - profit
      stop  = current_price + loss
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 決済注文を発注する
    # --------------------------------------------------------------------------
    send_parent_order(oposite_side: oposite_side,size: size,
      limit: limit,stop: stop)
    # --------------------------------------------------------------------------
  end

  def send_child_order(side:, size:)
    # puts "#{__method__}: ENTER(side: = #{side},size: = #{size})"
    with_retry() do
      s = {product_code: 'FX_BTC_JPY', child_order_type: 'MARKET',
        side: side, size: size}
      puts "#{__method__}: CALL: send_child_order(#{s})"
      r =  @private_client.send_child_order(s)
      puts "#{__method__}: r = #{r}"
      if r['status'] != nil
        sleep(0.1)
        raise "s=#{s}\nr=#{r}" # 発注失敗
      end
    end
    # puts "#{__method__}: EXIT"
  end

  def cancel_all_child_orders
    # puts "#{__method__}: ENTER"
    s = {product_code: 'FX_BTC_JPY'}
    puts "#{__method__}: CALL: cancel_all_child_orders(#{s})"
    r = @private_client.cancel_all_child_orders(s)
    puts "#{__method__}: r = #{r}"
    # puts "#{__method__}: EXIT"
  end

  def size_at_risk(current_price:, loss:, risk:)
    # puts "#{__method__}: ENTER"
    collateral = @private_client.collateral['collateral'] # 預入証拠金
    amount_at_risk = (collateral * risk).floor # 許容損失額（リスク）
    size = (amount_at_risk / loss).round(2)         # 売買するサイズ
    if (size * current_price) * 1.01 > collateral * 4     # 購入できるか？
      size = ((collateral * 4) / current_price).round(2)  # 購入できる取引量に
      size = (size * 100 - 1) / 100                       # 誤差修正
    end
    puts "#{__method__}: size = #{size}"
    # puts "#{__method__}: EXIT"
    size
  end

  def send_parent_order(oposite_side:,size:,limit:,stop:)
    # puts "#{__method__}: ENTER"
    parameters = [{
      "product_code": "FX_BTC_JPY",
      "condition_type": "STOP",
      "side": oposite_side,
      "trigger_price": stop,
      "size": size
    },
    {
      "product_code": "FX_BTC_JPY",
      "condition_type": "LIMIT",
      "side": oposite_side,
      "price": limit,
      "size": size
    }]

    with_retry() do
      s = {order_method: 'OCO', parameters: parameters}
      puts "#{__method__}: CALL send_parent_order(#{s})"
      r = @private_client.send_parent_order(s)
      puts "#{__method__}: r = #{r}"
      if r['status'] != nil
        raise "#{s}\n#{r}" # 発注失敗
      end
    end
    # puts "#{__method__}: EXIT"
  end
end