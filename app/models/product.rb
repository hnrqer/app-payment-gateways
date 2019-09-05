class Product < ActiveRecord::Base
  monetize :price_cents
  has_many :orders
end
