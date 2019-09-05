Rails.application.routes.draw do
  devise_for :users
  get '/', to: 'orders#index'
  post '/orders/submit', to: 'orders#submit'
end
