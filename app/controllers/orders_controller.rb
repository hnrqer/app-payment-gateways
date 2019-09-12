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
      @order = Orders::Paypal.finish(order_params[:charge_id])
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
    result = Orders::Paypal.create_payment(order: @order, product: @product)
    if result
      render json: { id: result }, status: :ok
    else
      render json: {error: FAILURE_MESSAGE}, status: :unprocessable_entity
    end
  end

  def paypal_execute_payment
    if Orders::Paypal.execute_payment(payment_id: params[:paymentID], payer_id: params[:payerID])
      render json: {}, status: :ok
    else
      render json: {error: FAILURE_MESSAGE}, status: :unprocessable_entity
    end
  end

  def paypal_create_subscription
    result = Orders::Paypal.create_subscription(order: @order, product: @product)
    if result
      render json: { id: result }, status: :ok
    else
      render json: {error: FAILURE_MESSAGE}, status: :unprocessable_entity
    end
  end

  def paypal_execute_subscription
    result = Orders::Paypal.execute_subscription(token: params[:paymentToken])
    if result
      render json: { id: result}, status: :ok
    else
      render json: {error: FAILURE_MESSAGE}, status: :unprocessable_entity
    end
  end

  private
  # Initialize a new order and and set its user, product and price.
  def prepare_new_order
    @order = Order.new(order_params)
    @order.user_id = current_user.id
    @product = Product.find(@order.product_id)
    @order.price_cents = @product.price_cents
  end

  def order_params
    params.require(:orders).permit(:product_id, :token, :payment_gateway, :charge_id)
  end
end
