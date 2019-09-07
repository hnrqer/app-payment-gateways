Rails.application.routes.draw do
  devise_for :users
  get '/', to: 'orders#index'
  post '/orders/submit', to: 'orders#submit'
  post 'orders/paypal/create_payment'  => 'orders#paypal_create_payment', as: :paypal_create_payment
  post 'orders/paypal/execute_payment'  => 'orders#paypal_execute_payment', as: :paypal_execute_payment
end
