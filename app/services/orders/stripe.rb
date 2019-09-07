class Orders::Stripe
  INVALID_STRIPE_OPERATION = 'Invalid Stripe Operation'
  def self.execute(order:, user:)
    product = order.product
    # Check if the order is a plan
    if product.stripe_plan_name.blank?
      charge = self.execute_payment(price_cents: product.price_cents,
                                    description: product.name,
                                    card_token:  order.token)
    else
      #PURCHASES WILL BE HANDLED HERE
    end
    unless charge&.id.blank?
      # If there is a charge with id, set order paid.
      order.charge_id = charge.id
      order.status = Order.statuses[:paid]
    end
  rescue Stripe::StripeError => e
    # If a Stripe error is raised from the API,
    # set status failed and an error message
    order.status = Order.statuses[:failed]
    order.error_message = INVALID_STRIPE_OPERATION
  end

  def self.execute_payment(price_cents:, description:, card_token:)
    Stripe::Charge.create({
      amount: price_cents.to_s,
      currency: "usd",
      description: description,
      source: card_token
    })
  end
end
