ENV['SSL_CERT_FILE'] = 'cacert.pem'

###### Required gems and files #####
require 'json'
require 'securerandom'
require 'peddler'
require 'pony'
require 'rest-client'
require 'time'
require 'csv'
require 'open-uri'
###### End Required gems and files #####

###### Basic Config Information #####
ZOOJI = "https://#{ENV['ZOOJI_SHOPIFY_API_KEY']}:#{ENV['ZOOJI_SHOPIFY_SHARED_SECRET']}@zooji.myshopify.com/admin"
ZOOSHOO = "https://#{ENV['ZOOSHOO_SHOPIFY_API_KEY']}:#{ENV['ZOOSHOO_SHOPIFY_SHARED_SECRET']}@zooshoo.myshopify.com/admin"
JADAMS = "https://#{ENV['JADAMS_SHOPIFY_API_KEY']}:#{ENV['JADAMS_SHOPIFY_SHARED_SECRET']}@j-adams.myshopify.com/admin"
###### Basic Config Information #####

###### Hash for easier Timeframe calculation ######
timeframes = {
	"today" => Time.now.iso8601,
	"yesterday" => (Time.now - (60 * 60 * 24)).iso8601,
	"seven_days" => (Time.now - (60 * 60 * 24 * 7)).iso8601,
	"fifteen_days" => (Time.now - (60 * 60 * 24  * 15)).iso8601,
	"thirty_days" => (Time.now - (60 * 60 * 24  * 30)).iso8601,
	"sixty_days" => (Time.now - (60 * 60 * 24  * 60)).iso8601,
	"ninety_days" => (Time.now - (60 * 60 * 24  * 90)).iso8601,
	"six_months" => (Time.now - (60 * 60 * 24  * 180)).iso8601,
	"year" => (Time.now - (60 * 60 * 24  * 365)).iso8601
}
###### Hash for easier Timeframe calculation ######

###### RestClient Wrapper ######
def request(url_base, request, url, params = nil)
	RestClient.send(request.to_sym, "#{url_base}#{url}.json", { params: params.to_h})
end
###### RestClient Wrapper ######

###### Grab Refund information from Shopify ######
def refund_info(dates, site)
	params, refunded_orders_ids, refunded_orders_names = [],[],[]
	refunded_orders_amount = 0

	params.push(['status', 'any'], ['financial_status', 'refunded'],['created_at_min', dates])
	refunded_orders = JSON.parse(request(site,'get', "/orders", params).body)
	refunded_orders_count = JSON.parse(request(site,'get', "/orders/count", params).body)
	
	refunded_orders['orders'].each do |order|
		refunded_orders_names.push(order['name'])
		refunded_orders_ids.push(order['id'])
		refunded_orders_amount = refunded_orders_amount + order['refunds'][0]['transactions'][0]['receipt']['TotalRefundedAmount'].to_i
	end
	
	refunded_orders['orders'][0]['refunds'][0]['transactions'][0]['receipt']['TotalRefundedAmount']

	refunds = {
		"count" => refunded_orders_count['count'],
		"order_ids" => refunded_orders_ids,
		"order_numbers" => refunded_orders_names,
		"refund_amounts" => refunded_orders_amount
	}
 end
###### Grab Refund information from Shopify ######

###### Grab Top Selling SKUs and Amount Sold for a Timeframe ######
def sales_info(dates, site)
	params, orders_ids, orders_names, all_skus, orders_request, orders = [],[],[],[],[],[]
	orders_amount = 0

	params.clear.push(['status', 'any'], ['financial_status', 'paid'],['created_at_min', dates])
	orders_count = JSON.parse(request(site,'get', "/orders/count", params).body)
	page_count = (orders_count['count']/250.to_f).ceil
	
	if page_count > 1
		i = 1
		while i < page_count + 1
			params.clear.push(['status', 'any'], ['financial_status', 'paid'],['created_at_min', dates],['limit', '250'],['page', i])	
			orders_request.push(request(site,'get', "/orders", params).body)
			i +=1
		end

		orders_request.each do |request|
			hashed_request = JSON.parse(request)
			hashed_request['orders'].each do |ind_order|
				orders << ind_order
			end
		end

		orders.each do |order|
			orders_names.push(order['name'])
			orders_ids.push(order['id'])
			order['line_items'].each {|line| all_skus.push(line['sku'])}
		end

	else
		params.clear.push(['status', 'any'], ['financial_status', 'paid'],['created_at_min', dates],['limit', '250'])
		orders = JSON.parse(request(site,'get', "/orders", params).body)
		orders['orders'].each do |order|
			orders_names.push(order['name'])
			orders_ids.push(order['id'])
			order['line_items'].each {|line| all_skus.push(line['sku'])}
		end
	end

	sales_info = {
		"count" => orders_count['count'],
		"order_ids" => orders_ids,
		"order_numbers" => orders_names,
		"refund_amounts" => orders_amount,
		"skus" => all_skus
	}
end
###### Grab Top Selling SKUs and Amount Sold for a Timeframe ######


###### Lookup an Order by Order Number ######
def order_lookup(order_name, site)
	if order_name.include? "ZJI"
		site = ZOOJI
	end
	params, order_info, skus = [], [], []
	params.push(['name',order_name],['status', 'any'])
	order = JSON.parse(request(site, 'get', "/orders", params).body)
	order_hash = order['orders'][0]

	order_hash['line_items'].each {|line| skus.push(line['sku'])}

	order_info = {
		"email" => order_hash['email'],
		"total_price" => order_hash['total_price'],
		"fulfillment_status" => order_hash['fulfillment_status'],
		"skus" => skus
	}
end
###### Lookup an Order by Order Number ######

###### Lookup a Customer ######
def customer_lookup(email, site)
	params, order_arr = [], []
	amount_spent = 0
	params.push(['query', email],['limit', 10])
	customer = JSON.parse(request(site, 'get', '/customers/search', params).body)
	customer_id = customer['customers'][0]['id']
	params.clear.push(['status', 'any'])
	customer_orders = JSON.parse(request(site, 'get', "/customers/#{customer_id}/orders", params).body)

	customer_orders['orders'].each do |order|
		amount_spent = amount_spent + order['total_price'].to_f
		order_arr.push(order['name'])
	end

	customer_info = {
		'order_count' => customer['customers'][0]['orders_count'],
		'all_orders' => order_arr,
		'most_recent_order' => order_arr[0],
		'amount_spent' => amount_spent.round(2)
	}

end
###### Lookup a Customer ######

def add_bulk_discounts(prefix, amt_discounts, site)
	batch_id = 0
	codes = ['discount_codes',[]]

	gen_codes = []
	i = 0

	while i < amt_discounts do
		code = prefix + SecureRandom.base64(10)
		codes[0][i] = code
	end
	puts codes
	# discounts = JSON.parse(request(site, 'post', "/price_rules/#{batch_id}/batch.json"))
end


#puts order_lookup("#105154", ZOOSHOO)

add_bulk_discounts("abc", 5, ZOOSHOO)