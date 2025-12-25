require "google_drive"
require "stringio" 

class GoogleSheetsService
  SHEET_ID = "1JMjHg3KxN1JvpESWKcwm5CSRTI1glFhUNJnJ_aa2aQE"
  
  def initialize
    # Kimlik bilgilerini getiren yardımcı metodu çağırıyoruz
    @session = GoogleDrive::Session.from_service_account_key(google_credentials)
    @spreadsheet = @session.spreadsheet_by_key(SHEET_ID)
    @worksheet = @spreadsheet.worksheets.first
  rescue => e
    # Hata durumunda loglama (CI tarafında neden patladığını görmek için)
    Rails.logger.error "Google Drive Bağlantı Hatası: #{e.message}"
    raise e
  end

  # ... (sync_to_sheet ve sync_from_sheet metodların aynı kalabilir)

  private

  def google_credentials
    # 1. Önce Environment Variable kontrol et (GitHub Actions ve Production için en iyisi)
    if ENV['GOOGLE_SERVICE_ACCOUNT_JSON'].present?
      # google_drive gem'i dosya yolu yerine bir IO nesnesi (StringIO) kabul eder
      return StringIO.new(ENV['GOOGLE_SERVICE_ACCOUNT_JSON'])
    end

    # 2. Eğer ENV yoksa yerel dosyaya bak (Local development için)
    file_path = Rails.root.join("config", "service_account.json")
    if File.exist?(file_path)
      return file_path.to_s
    end

    # 3. İkisi de yoksa hata fırlat
    raise "Google Service Account key bulunamadı! " \
          "Lütfen ENV['GOOGLE_SERVICE_ACCOUNT_JSON'] tanımlayın veya " \
          "config/service_account.json dosyasını oluşturun."
  end

  # DB -> Sheet (Export)
  def sync_to_sheet
    products = Product.all.order(:id)
    
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
      @worksheet[row, 7] = "" 
    end

    @worksheet.save
  end

  # Sheet -> DB (Import)
  def sync_from_sheet
    # Cache sorununu çözmek için reload
    @worksheet.reload
    
    return if @worksheet.num_rows < 2
    
    sheet_ids = [] # Silinmeyeceklerin listesi (Whitelist)

    (2..@worksheet.num_rows).each do |row|
      id_val = @worksheet[row, 1]
      name_val = @worksheet[row, 2]

      # Boş satırları atla
      next if name_val.blank?

      attrs = { 
        name:        @worksheet[row, 2], 
        description: @worksheet[row, 3], 
        price:       @worksheet[row, 4], 
        stock:       @worksheet[row, 5], 
        category:    @worksheet[row, 6] 
      }

      if id_val.present?
        # --- GÜNCELLEME SENARYOSU ---
        product = Product.find_by(id: id_val)
        if product
          sheet_ids << product.id # Mevcut ID'yi koruma altına al
          update_product(product, attrs, row)
        else
          # ID var ama DB'de yok -> Yeni yarat
          new_product = create_product(attrs, row)
          sheet_ids << new_product.id if new_product.persisted? # Yeni ID'yi koruma altına al!
        end
      else
        # --- YENİ KAYIT SENARYOSU ---
        new_product = create_product(attrs, row)
        sheet_ids << new_product.id if new_product.persisted? # Yeni ID'yi koruma altına al!
      end
    end

    # Whitelist'te olmayanları sil
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
      @worksheet[row, 1] = product.id # ID'yi Sheet'e yaz
      @worksheet[row, 7] = ""
    else
      @worksheet[row, 7] = product.errors.full_messages.join(", ")
    end
    
    return product # Ürün nesnesini geri döndür ki ID'sini alabilelim!
  end
end