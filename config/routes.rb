Rails.application.routes.draw do
  # Rails'in varsayılan sağlık kontrolü (Bunu koruyoruz)
  get "up" => "rails/health#show", as: :rails_health_check

  # Bizim eklediğimiz Product ve Sync rotaları
  resources :products do
    collection do
      post :sync_to_sheet
      post :sync_from_sheet
    end
  end

  # Uygulamanın açılış sayfası
  root "products#index"
end
