require "google_drive"

class GoogleSheetsService
  SHEET_ID = "1JMjHg3KxN1JvpESWKcwm5CSRTI1glFhUNJnJ_aa2aQE"
  
  def initialize
    @session = GoogleDrive::Session.from_service_account_key("config/service_account.json")
    @spreadsheet = @session.spreadsheet_by_key(SHEET_ID)
    @worksheet = @spreadsheet.worksheets.first
  end

  # DB -> Sheet (Export)
  def sync_to_sheet
    products = Product.all.order(:id)
    
    # Eski verileri temizle (Başlık hariç)
    if @worksheet.num_rows > 1
      @worksheet.delete_rows(2, @worksheet.num_rows - 1)
    end

    set_headers

    products.each_with_index do |product, index|
      row = index + 2
      @worksheet[row, 1] = product.id
      @worksheet[row, 2] = product.name
      @worksheet[row, 3] = product.description
      @worksheet[row, 4] = product.price
      @worksheet[row, 5] = product.stock
      @worksheet[row, 6] = product.category
      @worksheet[row, 7] = "" # Error kolonu
    end

    @worksheet.save
  end

  # Sheet -> DB (Import)
  def sync_from_sheet
    return if @worksheet.num_rows < 2
    sheet_ids = []

    (2..@worksheet.num_rows).each do |row|
      id = @worksheet[row, 1]
      
      # Hücreleri oku ve attribute hash'i oluştur
      attrs = { 
        name:        @worksheet[row, 2], 
        description: @worksheet[row, 3],
        price:       @worksheet[row, 4], 
        stock:       @worksheet[row, 5], 
        category:    @worksheet[row, 6] 
      }

      if id.present?
        product = Product.find_by(id: id)
        if product
          sheet_ids << product.id
          update_product(product, attrs, row)
        else
          # ID var ama DB'de yoksa yarat
          create_product(attrs, row)
        end
      else
        # ID yoksa yeni yarat
        create_product(attrs, row)
      end
    end

    # Sheet'ten silinenleri DB'den uçur
    Product.where.not(id: sheet_ids.compact).destroy_all
    @worksheet.save
  end

  private

  def set_headers
    @worksheet[1, 1] = "ID"
    @worksheet[1, 2] = "Name"
    @worksheet[1, 3] = "Description"
    @worksheet[1, 4] = "Price"
    @worksheet[1, 5] = "Stock"
    @worksheet[1, 6] = "Category"
    @worksheet[1, 7] = "Errors"
  end

  def update_product(product, attrs, row)
    if product.update(attrs)
      @worksheet[row, 7] = "" 
    else
      @worksheet[row, 7] = product.errors.full_messages.join(", ")
    end
  end

  def create_product(attrs, row)
    product = Product.new(attrs)
    if product.save
      @worksheet[row, 1] = product.id # ID'yi geri yaz
      @worksheet[row, 7] = ""
    else
      @worksheet[row, 7] = product.errors.full_messages.join(", ")
    end
  end
end