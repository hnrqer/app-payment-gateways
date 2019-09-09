class Orders::Stripe
  INVALID_STRIPE_OPERATION = 'Invalid Stripe Operation'
  def self.execute(order:, user:)
    product = order.product
    # Check if the order is a plan
    if product.stripe_plan_name.blank?
      charge = self.execute_charge(price_cents: product.price_cents,
                                    description: product.name,
                                    card_token:  order.token)
    else
      customer =  self.find_or_create_customer(card_token: order.token,
                                               customer_id: user.customer_id,
                                               email: user.email)
      if customer
        user.update(customer_id: customer.id)
        order.customer_id = customer.id
        charge = self.execute_subscription(plan: product.stripe_plan_name,
                                           token: order.token,
                                           customer: customer)
      end
    end
    unless charge&.id.blank?
      # If there is a charge with id, set order paid.
      order.charge_id = charge.id
      order.set_paid
    end
  rescue Stripe::StripeError => e
    # If a Stripe error is raised from the API,
    # set status failed and an error message
    order.error_message = INVALID_STRIPE_OPERATION
    order.set_failed
  end

  private
  def self.execute_charge(price_cents:, description:, card_token:)
    Stripe::Charge.create({
      amount: price_cents.to_s,
      currency: "usd",
      description: description,
      source: card_token
    })
  end

  def self.execute_subscription(plan:, token:, customer:)
    customer.subscriptions.create({
      plan: plan
    })
  end

  def self.find_or_create_customer(card_token:, customer_id:, email:)
    if customer_id
      stripe_customer = Stripe::Customer.retrieve({ id: customer_id })
      if stripe_customer
        stripe_customer = Stripe::Customer.update(stripe_customer.id, { source: card_token})
      end
    else
      stripe_customer = Stripe::Customer.create({
        email: email,
        source: card_token
      })
    end
    stripe_customer
  end
end
