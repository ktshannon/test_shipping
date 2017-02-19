class Order < ActiveRecord::Base

  ## These should be moved into .env variables depending your setup
  S3_ACCESS_KEY = "XXX"
  S3_SECRET = "XXX/XXX"
  S3_BUCKET = "XXX"
  UPS_ACCOUNT_NUMBER = "XXX"
  DEFAULT_UPS_SERVICE = "03" #GROUND
  UPS_TEST_MODE = TRUE

  # I'm still using the non yml, but can be ignored if usin yml setup
  UPS_LOGIN = "XXX"
  UPS_PASSWORD = "XXX"
  UPS_KEY = "XXX"

  DEFAULT_DIMENSIONS = {height: 12, width: 12, length: 12, weight: 5}

  def create_ups_shipment (from_address, to_address, dimensions = nil, return_code = nil)
    send_options = {}
    dimensions = DEFAULT_DIMENSIONS if dimensions.nil?

    ups = Omniship::UPS.new(:login => UPS_LOGIN, :password => UPS_PASSWORD, :key => UPS_KEY)
    if UPS_TEST_MODE == true
      ups.test_mode = true
      send_options[:test] = true
    end

    send_options[:origin_account]      = UPS_ACCOUNT_NUMBER  # replace with shipper account ID
    send_options[:service]             = DEFAULT_UPS_SERVICE # GROUND reference from the default services table
    if return_code
      send_options[:return_service_code] = "9"
      send_options[:shipper]             = to_address
    end

    response = ups.create_shipment(from_address, to_address, create_package(dimensions[:height],dimensions[:width],dimensions[:length],dimensions[:weight],return_code), options = send_options)
    return ups.accept_shipment(response)
  end

  def generate_both_labels(dimensions = nil?)
    dimensions = DEFAULT_DIMENSIONS unless dimensions.nil?

    send_shipment    = create_ups_shipment(parse_address(true), parse_address, dimensions)
    ship_labels = upload_label(send_shipment)

    self.ship_tracking_number   = send_shipment[:tracking_number].first
    self.ship_label_url         = ship_labels[:label_url]
    self.ship_label_url_zpl     = ship_labels[:zpl_url]

    return_shipment  = create_ups_shipment(parse_address, parse_address(true), dimensions, self.id)
    puts return_shipment
    return_labels = upload_label(return_shipment, true)

    self.return_tracking_number = return_shipment[:tracking_number].first
    self.return_label_url       = return_labels[:label_url]
    self.return_label_url_zpl   = return_labels[:zpl_url]

    self.save! # Update the order with the tracking and label/zpl urls
  end

  def parse_address (default_address = nil)
    address = {}
    if default_address
      address[:name]         = "PlatinumMix"
      address[:company_name] = "PlatinumMix"
      address[:address1]     = "123 Broadway"
      address[:city]         = "New York"
      address[:state]        = "NY"
      address[:zip]          = "10012"
      address[:phone]        = "1231231234"
      address[:country]      = "USA"
    else
      address[:name]         = self.name
      address[:company_name] = self.name
      address[:address1]     = self.address1
      address[:address2]     = self.address2
      address[:city]         = self.city
      address[:state]        = self.state
      address[:zip]          = self.zip
      address[:phone]        = self.phone
      address[:country]      = "USA" # I don't see any country field in your orders so defaulting USA
    end
    return Omniship::Address.new(address)
  end

  def create_package(height = 12, width = 12, length = 12, weight = 1, return_code = nil)
    pkg_list = []
    package_type = "02"

    # Package Metric Conversions
    height = height * 2.54
    width = width * 2.54
    length = length * 2.54
    weight = weight * 453.592
    # Package Metric Conversions

    options = {package_type: package_type, package_description: "Package Description", units: "imperial"}
    options[:references] = [{:code => "RZ", :value=>"RET #{return_code}"}] if return_code
    pkg_list << Omniship::Package.new(weight.to_i,[length.to_i,width.to_i,height.to_i],options)
    return pkg_list
  end

  def s3_connect
    Aws.config.update({
      region: 'us-east-2',
      credentials: Aws::Credentials.new(S3_ACCESS_KEY, S3_SECRET)
    })

    return Aws::S3::Resource.new
  end

  def upload_label(shipment, return_label = nil)
    s3 = s3_connect
    label_dir = (return_label.present?) ? "returns" : "shipping"
    tracking_number = shipment[:tracking_number].first
    label = Base64.decode64(shipment[:label].first)
    label_stamp = DateTime.now.strftime("%Y%m%m%H%M%s")

    File.open("#{Rails.root}/#{label_stamp}.png", 'wb') do |f|
      f.write(Base64.decode64(shipment[:label][0]))
    end
    file_date = DateTime.now.strftime("%Y%m%d")

    img_path = "labels/#{label_dir}/#{self.id}_#{tracking_number}_#{file_date}.jpg"
    zpl_path = "labels/#{label_dir}/#{self.id}_#{tracking_number}_#{file_date}.zpl"
    zpl_body = Labelary::Image.encode path: "#{Rails.root}/#{label_stamp}.png", mime_type: "image/png"

    bucket = s3.bucket(S3_BUCKET)

    # write label image
    label_obj = bucket.object(img_path)
    label_obj.put(body: label, acl: "public-read")

    # write zpl file
    zpl_obj = bucket.object(zpl_path)
    zpl_obj.put(body: "^XA#{zpl_body}^XZ", acl: "public-read")

    File.delete("#{Rails.root}/#{label_stamp}.png")

    return {label_url: label_obj.public_url, zpl_url: zpl_obj.public_url}
  end

end
