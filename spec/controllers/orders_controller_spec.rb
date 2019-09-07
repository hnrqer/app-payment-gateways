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

      def submit_order_and_check_success(check_customer_id: false)
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
        user.reload
        if (check_customer_id)
          expect(user.customer_id).to eq(new_customer_id)
        else
          expect(user.customer_id).to eq(nil)
        end
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

      describe "plan" do
        let!(:product) { create(:product, :with_plan) }
        let!(:new_customer_id) { "stripe-customer-id-new" }
        let!(:res_subscription_create) { double(id: stripe_charge_id) }
        let!(:res_customer) { double(id: new_customer_id, subscriptions: res_subscription_create) }

        describe "without customer" do
          it "performs order successfully" do
            allow(Stripe::Customer).to receive(:create).and_return(res_customer)
            expect(Stripe::Customer).to receive(:create).with({ email: user.email, source: token })
            allow(res_subscription_create).to receive(:create).and_return(res_subscription_create)
            expect(res_subscription_create).to receive(:create).with({
              plan: product.stripe_plan_name
            })
            submit_order_and_check_success(check_customer_id: true)
          end

          it "fails if customer create fail" do
            allow(Stripe::Customer).to receive(:create).and_raise(Stripe::CardError.new(nil,nil))
            expect(Stripe::Customer).to receive(:create).with({ email: user.email, source: token })
            submit_order_and_check_failed
          end

          it "fails if customer create fail" do
            allow(Stripe::Customer).to receive(:create).and_return(res_customer)
            expect(Stripe::Customer).to receive(:create).with({ email: user.email, source: token })
            allow(res_subscription_create).to receive(:create).and_raise(Stripe::CardError.new(nil,nil))
            expect(res_subscription_create).to receive(:create).with({
              plan: product.stripe_plan_name
            })
            submit_order_and_check_failed
          end
        end

        describe "with customer" do
          before(:each) { user.update(customer_id: 'stripe-customer-id') }
          it "performs order successfully" do
            allow(Stripe::Customer).to receive(:retrieve).and_return(res_customer)
            expect(Stripe::Customer).to receive(:retrieve).with({ id: user.customer_id })
            allow(Stripe::Customer).to receive(:update).and_return(res_customer)
            expect(Stripe::Customer).to receive(:update).with(new_customer_id, { source: token })
            allow(res_subscription_create).to receive(:create).and_return(res_subscription_create)
            expect(res_subscription_create).to receive(:create).with({
              plan: product.stripe_plan_name
            })
            submit_order_and_check_success(check_customer_id: true)
          end

          it "fails if customer retrieve fail" do
            allow(Stripe::Customer).to receive(:retrieve).and_raise(Stripe::CardError.new(nil,nil))
            expect(Stripe::Customer).to receive(:retrieve).with({ id: user.customer_id })
            submit_order_and_check_failed
          end
          it "fails if customer update fail" do
            allow(Stripe::Customer).to receive(:retrieve).and_return(res_customer)
            expect(Stripe::Customer).to receive(:retrieve).with({ id: user.customer_id })
            allow(Stripe::Customer).to receive(:update).and_raise(Stripe::CardError.new(nil,nil))
            expect(Stripe::Customer).to receive(:update).with(new_customer_id, { source: token })
            submit_order_and_check_failed
          end
          it "fails if customer subscription create fail" do
            allow(Stripe::Customer).to receive(:retrieve).and_return(res_customer)
            expect(Stripe::Customer).to receive(:retrieve).with({ id: user.customer_id })
            allow(Stripe::Customer).to receive(:update).and_return(res_customer)
            expect(Stripe::Customer).to receive(:update).with(new_customer_id, { source: token })
            allow(res_subscription_create).to receive(:create).and_raise(Stripe::CardError.new(nil,nil))
            expect(res_subscription_create).to receive(:create).with({
              plan: product.stripe_plan_name
            })
            submit_order_and_check_failed
          end
        end
      end
    end
  end
end
