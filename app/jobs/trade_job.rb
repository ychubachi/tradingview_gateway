class TradeJob < ApplicationJob
  queue_as :default

  def perform(*args)
    # Do something later
    puts 'TRADE!!'
  end
end
