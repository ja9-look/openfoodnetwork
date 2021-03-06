require "spec_helper"

feature %q{
    As an admin
    I want to set a supplier and distributor(s) for a product
} do
  include AuthenticationWorkflow
  include WebHelper


  let!(:taxon) { create(:taxon) }
  let!(:stock_location) { create(:stock_location, backorderable_default: false) }
  let!(:shipping_category) { create(:shipping_category, name: 'Test Shipping Category') }

  background do
    @supplier = create(:supplier_enterprise, :name => 'New supplier')
    @distributors = (1..3).map { create(:distributor_enterprise) }
    @enterprise_fees = (0..2).map { |i| create(:enterprise_fee, enterprise: @distributors[i]) }
  end

  describe "creating a product" do
    let!(:tax_category) { create(:tax_category, name: 'Test Tax Category') }

    scenario "assigning important attributes", js: true do
      login_to_admin_section

      click_link 'Products'
      click_link 'New Product'

      select 'New supplier', from: 'product_supplier_id'
      fill_in 'product_name', with: 'A new product !!!'
      select "Weight (kg)", from: 'product_variant_unit_with_scale'
      fill_in 'product_unit_value_with_description', with: 5
      select taxon.name, from: "product_primary_taxon_id"
      fill_in 'product_price', with: '19.99'
      fill_in 'product_on_hand', with: 5
      select 'Test Tax Category', from: 'product_tax_category_id'
      select 'Test Shipping Category', from: 'product_shipping_category_id'
      page.find("div[id^='taTextElement']").native.send_keys('A description...')

      click_button 'Create'

      expect(current_path).to eq spree.admin_products_path
      flash_message.should == 'Product "A new product !!!" has been successfully created!'
      product = Spree::Product.find_by_name('A new product !!!')
      product.supplier.should == @supplier
      product.variant_unit.should == 'weight'
      product.variant_unit_scale.should == 1000
      product.unit_value.should == 5000
      product.unit_description.should == ""
      product.variant_unit_name.should == ""
      product.primary_taxon_id.should == taxon.id
      product.price.to_s.should == '19.99'
      product.on_hand.should == 5
      product.tax_category_id.should == tax_category.id
      product.shipping_category.should == shipping_category
      product.description.should == "<p>A description...</p>"
      product.group_buy.should be_falsey
      product.master.option_values.map(&:name).should == ['5kg']
      product.master.options_text.should == "5kg"
    end

    scenario "creating an on-demand product", js: true do
      quick_login_as_admin
      visit spree.admin_products_path

      click_link 'New Product'

      fill_in 'product_name', with: 'Hot Cakes'
      select 'New supplier', from: 'product_supplier_id'
      select "Weight (kg)", from: 'product_variant_unit_with_scale'
      fill_in 'product_unit_value_with_description', with: 1
      select taxon.name, from: "product_primary_taxon_id"
      fill_in 'product_price', with: '1.99'
      fill_in 'product_on_hand', with: 0
      check 'product_on_demand'
      select 'Test Tax Category', from: 'product_tax_category_id'
      select 'Test Shipping Category', from: 'product_shipping_category_id'
      page.find("div[id^='taTextElement']").native.send_keys('In demand, and on_demand! The hottest cakes in town.')

      click_button 'Create'

      expect(current_path).to eq spree.admin_products_path
      product = Spree::Product.find_by_name('Hot Cakes')
      product.variants.count.should == 1
      variant = product.variants.first
      variant.on_demand.should be true
    end
  end

  context "as an enterprise user" do
    let!(:tax_category) { create(:tax_category) }

    before do
      @new_user = create_enterprise_user
      @supplier2 = create(:supplier_enterprise, name: 'Another Supplier')
      @supplier_permitted = create(:supplier_enterprise, name: 'Permitted Supplier')
      @new_user.enterprise_roles.build(enterprise: @supplier2).save
      @new_user.enterprise_roles.build(enterprise: @distributors[0]).save
      create(:enterprise_relationship, parent: @supplier_permitted, child: @supplier2,
             permissions_list: [:manage_products])

      quick_login_as @new_user
    end

    context "products do not require a tax category" do
      scenario "creating a new product", js: true do
        with_products_require_tax_category(false) do
          visit spree.admin_products_path
          click_link 'New Product'

          fill_in 'product_name', :with => 'A new product !!!'
          fill_in 'product_price', :with => '19.99'

          page.should have_selector('#product_supplier_id')
          select 'Another Supplier', :from => 'product_supplier_id'
          select 'Weight (g)', from: 'product_variant_unit_with_scale'
          fill_in 'product_unit_value_with_description', with: '500'
          select taxon.name, from: "product_primary_taxon_id"
          select 'Test Shipping Category', from: 'product_shipping_category_id'
          select 'None', from: "product_tax_category_id"

          # Should only have suppliers listed which the user can manage
          page.should have_select 'product_supplier_id', with_options: [@supplier2.name, @supplier_permitted.name]
          page.should_not have_select 'product_supplier_id', with_options: [@supplier.name]

          click_button 'Create'

          flash_message.should == 'Product "A new product !!!" has been successfully created!'
          product = Spree::Product.find_by_name('A new product !!!')
          product.supplier.should == @supplier2
          product.tax_category.should be_nil
        end
      end
    end

    scenario "editing a product" do
      product = create(:simple_product, name: 'a product', supplier: @supplier2)

      visit spree.edit_admin_product_path product

      select 'Permitted Supplier', from: 'product_supplier_id'
      select tax_category.name, from: 'product_tax_category_id'
      click_button 'Update'
      flash_message.should == 'Product "a product" has been successfully updated!'
      product.reload
      product.supplier.should == @supplier_permitted
      product.tax_category.should == tax_category
    end

    scenario "editing product group buy options" do
      product = product = create(:simple_product, supplier: @supplier2)

      visit spree.edit_admin_product_path product
      within('#sidebar') { click_link 'Group Buy Options' }
      choose('product_group_buy_1')
      fill_in 'Bulk unit size', :with => '10'

      click_button 'Update'

      flash_message.should == "Product \"#{product.name}\" has been successfully updated!"
      product.reload
      product.group_buy.should be true
      product.group_buy_unit_size.should == 10.0
    end

    scenario "editing product Search" do
      product = product = create(:simple_product, supplier: @supplier2)
      visit spree.edit_admin_product_path product
      within('#sidebar') { click_link 'Search' }
      fill_in 'Product Search Keywords', :with => 'Product Search Keywords'
      fill_in 'Notes', :with => 'Just testing Notes'
      click_button 'Update'
      expect(flash_message).to eq("Product \"#{product.name}\" has been successfully updated!")
      product.reload
      expect(product.notes).to eq('Just testing Notes')
      expect(product.meta_keywords).to eq('Product Search Keywords')
    end

    scenario "deleting product properties", js: true do
      # Given a product with a property
      p = create(:simple_product, supplier: @supplier2)
      p.set_property('fooprop', 'fooval')

      # When I navigate to the product properties page
      visit spree.admin_product_product_properties_path(p)
      page.should have_select2 'product_product_properties_attributes_0_property_name', selected: 'fooprop'
      page.should have_field 'product_product_properties_attributes_0_value', with: 'fooval'

      # And I delete the property
      accept_alert do
        page.all('a.delete-resource').first.click
      end
      click_button 'Update'

      # Then the property should have been deleted
      page.should_not have_field 'product_product_properties_attributes_0_property_name', with: 'fooprop'
      page.should_not have_field 'product_product_properties_attributes_0_value', with: 'fooval'
      expect(p.reload.property('fooprop')).to be_nil
    end


    scenario "deleting product images", js: true do
      product = create(:simple_product, supplier: @supplier2)
      image = File.open(File.expand_path('../../../../app/assets/images/logo-white.png', __FILE__))
      Spree::Image.create({:viewable_id => product.master.id, :viewable_type => 'Spree::Variant', :alt => "position 1", :attachment => image, :position => 1})

      visit spree.admin_product_images_path(product)
      page.should have_selector "table[data-hook='images_table'] td img"
      expect(product.reload.images.count).to eq 1

      accept_alert do
        page.find('a.delete-resource').click
      end

      expect(page).to_not have_selector "table[data-hook='images_table'] td img"
      expect(product.reload.images.count).to eq 0
    end
  end
end
