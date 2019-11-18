require "oanda_api_v20"

class OandaGateway
  def initialize(account_id, token, practice = true)
    @account_id = account_id
    @token = token
    @client = OandaApiV20.new(access_token: token, practice: practice)
  end

  def buy(instrument = 'USD_JPY', units = 100)
    options = {
      'order' => {
        'units' => units,
        'instrument' => instrument,
        'timeInForce' => 'FOK',
        'type' => 'MARKET',
        'positionFill' => 'DEFAULT'
      }
    }
    @client.account(@account_id).order(options).create
  end

  def sell(instrument = 'USD_JPY', units = 100)
    options = {
      'order' => {
        'units' => - units,
        'instrument' => instrument,
        'timeInForce' => 'FOK',
        'type' => 'MARKET',
        'positionFill' => 'DEFAULT'
      }
    }

    @client.account(@account_id).order(options).create
  end

  def close_all(instrument = 'USD_JPY')
    units = position_units(instrument)
    if units[:long] > 0
      sell(instrument, units[:long])
    elsif units[:short] > 0
      buy(instrument, units[:short])
    end
  end

  def position_units(instrument = 'USD_JPY')
    positions = @client.account(@account_id).positions.show
    long = 0
    short = 0
    positions['positions'].each do |postion|
      if postion['instrument'] == instrument
        long  += postion['long'] ['units'].to_i
        short += postion['short']['units'].to_i
      end
    end
    {long: long, short: -short} # short is negative value originally
  end
end
