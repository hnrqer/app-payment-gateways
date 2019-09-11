class OrdersController < ApplicationController
  before_action :authenticate_user!
  before_action :prepare_new_order, only: [:paypal_create_payment, :paypal_create_subscription]

  SUCCESS_MESSAGE = 'Order Performed Successfully!'
  FAILURE_MESSAGE = 'Oops something went wrong. Please call the administrator'

  def index
    products = Product.all
    @products_purchase = products.where(stripe_plan_name:nil, paypal_plan_name:nil)
    @products_subscription = products - @products_purchase
  end

  def submit
    @order = nil
    #Check which type of order it is
    if order_params[:payment_gateway] == "stripe"
      prepare_new_order
      Orders::Stripe.execute(order: @order, user: current_user)
    elsif order_params[:payment_gateway] == "paypal"
      @order = Orders::Paypal.execute(order_params[:token])
    end
  ensure
    if @order&.save
      if @order.paid?
        # Success is rendere when order is paid and saved
        return render html: SUCCESS_MESSAGE
      elsif @order.failed? && !@order.error_message.blank?
        # Render error only if order failed and there is an error_message
        return render html: @order.error_message
      end
    end
    render html: FAILURE_MESSAGE
  end

  def paypal_create_payment
    paypal_process_create_order(&Orders::Paypal.method(:create_payment))
  end

  def paypal_execute_payment
    options = {token: params[:paymentID], payer_id: params[:payerID]}
    paypal_process_execute_order(options, &Orders::Paypal.method(:execute_payment))
  end

  def paypal_create_subscription
    paypal_process_create_order(&Orders::Paypal.method(:create_subscription))
  end

  def paypal_execute_subscription
    options = {token: params[:paymentToken]}
    paypal_process_execute_order(options, &Orders::Paypal.method(:execute_subscription))
  end

  private
  def paypal_process_execute_order(**options, &callback)
    @order = Orders::Paypal.find_order_by_token(options[:token])
    if @order && callback.call(options)
      @order.set_paypal_executed
      render json: {}, status: :ok if @order.save
    else
      render json: {error: FAILURE_MESSAGE},
        status: :unprocessable_entity
    end
  end

  def paypal_process_create_order(&callback)
    response = callback.call(product: @product)
    if response[:success]
      @order.token = response[:id]
    else
      @order.set_failed
    end
  ensure
    if @order.save && @order.pending? && defined?(response) && !response.nil? && response.key?(:id)
      render json: { id: response[:id] }, status: :ok
    else
      render json: {error: FAILURE_MESSAGE},
        status: :unprocessable_entity
    end
  end
  # Initialize a new order and and set its user, product and price.
  def prepare_new_order
    @order = Order.new(order_params)
    @order.user_id = current_user.id
    @product = Product.find(@order.product_id)
    @order.price_cents = @product.price_cents
  end

  def order_params
    params.require(:orders).permit(:product_id, :token, :payment_gateway)
  end
end
