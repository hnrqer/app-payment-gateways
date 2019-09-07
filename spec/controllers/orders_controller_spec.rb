require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  include Devise::Test::ControllerHelpers
  let(:user) { create(:user) }
  let(:token)    { "ToKeN1!2@3#" }
  before(:each) do
    sign_in(user)
  end

  describe "#index" do
    before(:each) do
      sign_in(user)
    end
    it 'renders index' do
       get :index
       expect(response).to render_template :index
    end
    describe "with purchase products only" do
      let!(:purchase_product) { create(:product) }
      it do
         get :index
         expect(assigns[:products_purchase].count).to eq Product.all.count
         expect(assigns[:products_subscription].count).to eq 0
      end
    end

    describe "with plan products only" do
      let!(:plan_product) { create(:product, :with_plan) }
      it do
        get :index
        expect(assigns[:products_purchase].count).to eq 0
        expect(assigns[:products_subscription].count).to eq Product.all.count
      end
    end

    describe "without_products" do
      it do
        get :index
        expect(assigns[:products_purchase].count).to eq 0
        expect(assigns[:products_subscription].count).to eq 0
      end
    end

    describe "with purchase and plan products" do
      let!(:purchase_product) { create(:product) }
      let!(:plan_product) { create(:product, :with_plan) }
      it do
        get :index
        expect(assigns[:products_purchase].count).to eq 1
        expect(assigns[:products_subscription].count).to eq 1
      end
    end
  end

  describe "#submit" do
    describe 'stripe' do
      let(:params) { { orders: { product_id: product.id, token:  token, payment_gateway: 'stripe' } } }
      let!(:stripe_charge_id) { "stripe_charge_id1234" }

      def submit_order_and_check_failed
        expect {
          post :submit, params: params
        }.to change(Order, :count).by(1)
        expect(response).to be_successful
        expect(response.body).to eq(Orders::Stripe::INVALID_STRIPE_OPERATION)
        order = Order.last
        user.reload
        expect(order.user).to eq(user)
        expect(order.product).to eq(product)
        expect(order.price_cents).to eq(product.price_cents)
        expect(order.charge_id).to be_nil
        expect(order.token).to eq(token)
        expect(order.failed?).to be_truthy
        expect(order.error_message).to be_present
      end

      def submit_order_and_check_success
        expect {
          post :submit, params: params
        }.to change(Order, :count).by(1)
        order = Order.last
        expect(response).to be_successful
        expect(response.body).to eq(OrdersController::SUCCESS_MESSAGE)
        expect(order.user).to eq(user)
        expect(order.product).to eq(product)
        expect(order.token).to eq(token)
        expect(order.price_cents).to eq(product.price_cents)
        expect(order.paid?).to be_truthy
        expect(order.charge_id).to eq(stripe_charge_id)
      end

      describe "purchase" do
        let!(:product) { create(:product) }
        it "performs order successfully" do
          res = double(id: stripe_charge_id)
          allow(Stripe::Charge).to receive(:create).and_return(res)
          expect(Stripe::Charge).to receive(:create).with({
            amount: product.price_cents.to_s,
            currency: "usd",
            description: product.name,
            source: token
          })
          submit_order_and_check_success
        end

        it "fails if exception when stripe charge" do
          allow(Stripe::Charge).to receive(:create).and_raise(Stripe::CardError.new(nil,nil))
          submit_order_and_check_failed
        end
      end
    end
  end
end
