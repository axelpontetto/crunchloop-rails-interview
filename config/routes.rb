Rails.application.routes.draw do
  namespace :api do
    resources :todo_lists, only: %i[index], path: :todolists
  end

  resources :todo_lists, path: :todolists do
    resources :todo_items, path: :todoitems do
      patch :check_all, on: :collection
    end
  end

  root "todo_lists#index"
end
