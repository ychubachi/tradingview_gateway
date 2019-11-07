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

  def position_price
    puts "#{__method__}: ENTER"

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
    puts "#{__method__}: EXIT"
    avg_price
  end

  def order(side: nil, size: nil, profit: 1000.0, loss: 1000.0, risk: 0.02)
    puts "#{__method__}: ENTER"
    puts "#{__method__}: side = #{side}, size = #{size}, " +
      "profit = #{profit}, loss = #{loss}, risk = #{risk}"

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
      collateral = @private_client.collateral['collateral'] # 預入証拠金
      amount_at_risk = (collateral * risk).floor # 許容損失額（リスク）
      size = (amount_at_risk / loss).round(2)         # 売買するサイズ
      if (size * current_price) * 1.01 > collateral * 4     # 購入できるか？
        size = ((collateral * 4) / current_price).round(2)  # 購入できる取引量に
        size = (size * 100 - 1) / 100                       # 誤差修正
      end
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 注文を発注する
    # --------------------------------------------------------------------------
    s = {product_code: 'FX_BTC_JPY',
      child_order_type: 'MARKET', side: side, size: size}
    puts "#{__method__}: CALL: send_child_order(#{s})"
    r =  @private_client.send_child_order(s)
    puts "#{__method__}: r = #{r}"
    if r['status'] != nil
      raise "#{s}\n#{r}" # 発注失敗
    end
    # --------------------------------------------------------------------------

    # ==========================================================================
    # 平均取得単価を求める
    # --------------------------------------------------------------------------
    begin
      current_price = position_price
    rescue
      puts 'could not get position price. use mid price.'
    end
    puts "#{__method__}: #{current_price}"

    # ==========================================================================
    # 決済注文を発注する
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

    puts "#{__method__}: CALL send_parent_order"
    puts "#{__method__}: parameters = #{parameters}"
    r = @private_client.send_parent_order(
        order_method: 'OCO', parameters: parameters)
    puts "#{__method__}: r = #{r}"
    if r['status'] != nil
      raise r.to_s # 発注失敗
    end
    puts "#{__method__}: EXIT"
  end
end
