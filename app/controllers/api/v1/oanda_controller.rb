require "oanda_api_v20"

module Api
  module V1
    class OandaController < ApplicationController
      before_action :set_oanda, only: [:show, :update, :destroy]

      def index
        oandas = Oanda.order(created_at: :desc)
        render json: { status: 'SUCCESS', message: 'Loaded oandas', data: oandas }
      end

      def show
        render json: { status: 'SUCCESS', message: 'Loaded the oanda', data: @oanda }
      end

      def create
        oanda = Oanda.new(oanda_params)
        if oanda.save
          render json: { status: 'SUCCESS', data: oanda }
        else
          render json: { status: 'ERROR', data: oanda.errors }
        end

        account_id = params['account_id']
        p "account_id=" + account_id
        token = ENV['OANDA_TOKEN']
        gateway = OandaGateway.new(account_id, token, practice = true)

        case oanda.strategy
        when 'long'
          units = gateway.position_units
          if units[:long] == 0
            if units[:short] > 0
              gateway.close_all()
            end
            gateway.buy(instrument = oanda.instrument, units = oanda.qty)
          end
        when 'short'
          units = gateway.position_units()
          if units[:short] == 0
            if units[:long] > 0
              gateway.close_all()
            end
            gateway.sell(instrument = oanda.instrument, units = oanda.qty)
          end
        when 'close_all'
          gateway.close_all()
        end

      end

      def destroy
        @oanda.destroy
        render json: { status: 'SUCCESS', message: 'Deleted the oanda', data: @oanda }
      end

      def update
        if @oanda.update(oanda_params)
          render json: { status: 'SUCCESS', message: 'Updated the oanda', data: @oanda }
        else
          render json: { status: 'SUCCESS', message: 'Not updated', data: @oanda.errors }
        end
      end

      private

      def set_oanda
        @oanda = Oanda.find(params[:id])
      end

      def oanda_params
        params.require(:oanda).permit(:instrument, :strategy, :qty)
      end

    end
  end
end

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
