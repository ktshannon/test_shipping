class CreateOrders < ActiveRecord::Migration
  def change
    create_table :orders do |t|
      t.string :name
      t.string :address1
      t.string :address2
      t.string :city
      t.string :state
      t.string :zip
      t.string :phone
      t.string :ship_tracking_number
      t.string :ship_label_url
      t.string :ship_label_url_zpl
      t.string :return_tracking_number
      t.string :return_label_url
      t.string :return_label_url_zpl

      t.timestamps null: false
    end
  end
end
