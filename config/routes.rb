require 'sidekiq/web'

Rails.application.routes.draw do
  namespace 'api' do
    namespace 'v1' do
      resources :alerts
      resources :oanda
    end
  end

  mount Sidekiq::Web => '/sidekiq'
end
