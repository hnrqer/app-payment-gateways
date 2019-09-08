class Orders::Paypal
  def self.execute(token)
    order = Order.paypal_executed.where(token: token).last
    return nil if order.nil?
    order.charge_id = order.token
    order.token = nil
    order.set_paid
    order
  end

  def self.find_order_by_token(token)
    Order.find_by(token: token)
  end

  def self.create_payment(product:)
    payment_price = (product.price_cents/100.0).to_s
    currency = "USD"
    payment = PayPal::SDK::REST::Payment.new({
      intent:  "sale",
      payer:  {
        payment_method: "paypal" },
      redirect_urls: {
        return_url: "/",
        cancel_url: "/" },
      transactions:  [{
        item_list: {
          items: [{
            name: product.name,
            sku: product.name,
            price: payment_price,
            currency: currency,
            quantity: 1 }
            ]
          },
        amount:  {
          total: payment_price,
          currency: currency
        },
        description:  "Payment for: #{product.name}"
      }]
    })
    result = payment.create
    id = result ? payment.id : nil
    return {success: result, id: payment.id}
  end

  def self.execute_payment(token:, payer_id:)
    payment = PayPal::SDK::REST::Payment.find(token)
    payment.execute( payer_id: payer_id )
  end
end
