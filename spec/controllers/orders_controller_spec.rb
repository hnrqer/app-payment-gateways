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
end
