require 'oanda_gateway'

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

        if oanda.save
          render json: { status: 'SUCCESS', data: oanda }
        else
          render json: { status: 'ERROR', data: oanda.errors }
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
