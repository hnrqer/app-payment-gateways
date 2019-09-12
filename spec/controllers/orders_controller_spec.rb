require 'rails_helper'

RSpec.describe OrdersController, type: :controller do
  include Devise::Test::ControllerHelpers
  let(:user) { create(:user) }
  let(:token)    { "ToKeN1!2@3#" }
  let(:paypal_charge_id) {"PAYID123456789"}
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

    describe 'paypal' do
      let(:product) { create(:product) }
      let(:params)  { { orders: { product_id: product.id, token:  token, payment_gateway: 'paypal' } } }
      describe "Success" do
        let!(:order) { create(:order, status: :paypal_executed, token: token) }
        it "Performs order succesfully" do
          post :submit, params: params
          expect(response.body).to eq(OrdersController::SUCCESS_MESSAGE)
          order.reload
          expect(order.paid?).to be_truthy
        end
      end

      describe "Fails - if order is in incorrect state" do
        let!(:order) { create(:order, status: :pending, charge_id: paypal_charge_id) }
        it do
          post :submit, params: params
          expect(response.body).to eq(OrdersController::FAILURE_MESSAGE)
          order.reload
          expect(order.paid?).to be_falsy
        end
      end

      describe "Fails - if order not found" do
        let!(:order) { create(:order, status: :paypal_executed, charge_id: paypal_charge_id + 'a') }
        it do
          post :submit, params: params
          expect(response.body).to eq(OrdersController::FAILURE_MESSAGE)
          order.reload
          expect(order.paid?).to be_falsy
        end
      end

      after(:each) do
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "paypal" do
    describe "create" do
      let(:params)  {{ orders: { product_id: product.id, payment_gateway: 'paypal' }}}
      shared_examples :paypal_create_ok do
        it do
          expect {
            post action, params: params
          }.to change(Order, :count).by(1)
          order = Order.last
          expect(response).to be_successful
          expect(order.user).to eq(user)
          expect(order.token).to eq(token)
          expect(order.product).to eq(product)
          expect(order.price_cents).to eq(product.price_cents)
          expect(order.pending?).to be_truthy
          if order.product.paypal_plan_name.blank?
            expect(order.charge_id).to eq(paypal_charge_id)
            expect(JSON.parse(response.body)["id"]).to eq(paypal_charge_id)
          else
            expect(JSON.parse(response.body)["id"]).to eq(token)
          end
        end
      end

      shared_examples :paypal_create_fail do
        it do
          expect {
            post action, params: params
          }.to change(Order, :count).by(0)
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)["error"]).to be_present
        end
      end

      describe "#paypal_create_payment" do
        let!(:product) { create(:product) }
        let(:action)   {:paypal_create_payment}
        def prepare(pass:)
          res = double(id: paypal_charge_id, token: token, create: pass)
          allow(PayPal::SDK::REST::Payment).to receive(:new).and_return(res)
          expect(PayPal::SDK::REST::Payment).to receive(:new).with(req_new_payment(product))
        end
        describe "success" do
          before(:each) { prepare(pass:true) }
          it_behaves_like :paypal_create_ok
          after do

          end
        end
        describe "failure" do
          before(:each) { prepare(pass:false) }
          it_behaves_like :paypal_create_fail
        end

        def req_new_payment(product, currency: "USD")
          {
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
                  price: (product.price_cents/100.0).to_s,
                  currency: currency,
                  quantity: 1 }
                  ]
                },
              amount: {
                total: (product.price_cents/100.0).to_s,
                currency: currency
              },
              description: "Payment for: #{product.name}"
            }]
          }
        end
      end
      describe "#paypal_create_subscription" do
        let!(:product) { create(:product , :with_plan) }
        let(:action)   {:paypal_create_subscription}
        def prepare(pass:)
          res = double(token: token, create: pass)
          allow(PayPal::SDK::REST::Agreement).to receive(:new).and_return(res)
          expect(PayPal::SDK::REST::Agreement).to receive(:new).with(req_new_subscription(product))
        end

        describe "success" do
          before(:each) { prepare(pass:true) }
          it_behaves_like :paypal_create_ok
        end

        describe "failure" do
          before(:each) { prepare(pass:false) }
          it_behaves_like :paypal_create_fail
        end

        def req_new_subscription(product)
          {
            name: product.name,
            description: "Subscription for: #{product.name}",
            start_date: anything(),
            payer: {
              payment_method: "paypal"
            },
            plan: {
              id: product.paypal_plan_name
            }
          }
        end
      end
    end

    describe "execute" do
      let!(:order) { create(:order) }
      shared_examples :paypal_execute_ok do
        it do
          post action, params: params
          expect(response).to be_successful
          order.reload
          expect(order.paypal_executed?).to be_truthy
          unless order.product.paypal_plan_name.blank?
            expect(order.charge_id).to eq(paypal_charge_id)
            expect(JSON.parse(response.body)["id"]).to eq(paypal_charge_id)
          end
        end
      end

      shared_examples :paypal_execute_fail do
        it do
          post action, params: params
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)["error"]).to be_present
        end
      end

      shared_examples :paypal_execute_not_found do
        it do
          post action, params: params
          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)["error"]).to be_present
          order.reload
          expect(order.pending?).to be_truthy
        end
      end

      describe "#paypal_execute_payment" do
        let!(:product) { create(:product) }
        let(:action)   {:paypal_execute_payment}
        let(:params) { { paymentID: paypal_charge_id, payerID: 'test-payer-id' } }
        def prepare(pass:)
          res = double
          allow(res).to receive(:execute).and_return(pass)
          allow(PayPal::SDK::REST::Payment).to receive(:find).and_return(res)
          expect(PayPal::SDK::REST::Payment).to receive(:find).with(paypal_charge_id)
          expect(res).to receive(:execute).with(payer_id: params[:payerID])
        end

        describe "success" do
          before do
            order.update(charge_id: paypal_charge_id)
            prepare(pass: true)
          end
          it_behaves_like :paypal_execute_ok
        end

        describe "failure" do
          before do
            order.update(charge_id: paypal_charge_id)
            prepare(pass: false)
          end
          it_behaves_like :paypal_execute_fail
        end

        describe "failure - not found" do
          it_behaves_like :paypal_execute_not_found
        end
      end
      describe "#paypal_execute_subscription" do
        let!(:product) { create(:product, :with_plan) }
        let(:action)   {:paypal_execute_subscription}
        let(:params) { { paymentToken: token } }
        def prepare(pass:)
          res = OpenStruct.new(execute: pass, id: paypal_charge_id)
          allow(PayPal::SDK::REST::Agreement).to receive(:new).and_return(res)
        end

        describe "success" do
          before do
            order.update(token: token)
            prepare(pass: true)
          end
          it_behaves_like :paypal_execute_ok
        end

        describe "failure" do
          before do
            order.update(token: token)
            prepare(pass: false)
          end
          it_behaves_like :paypal_execute_fail
        end

        describe "failure - not found" do
          before { order.update(token: token.reverse) }
          it_behaves_like :paypal_execute_not_found
        end
      end
    end
  end
end
