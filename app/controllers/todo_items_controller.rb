class TodoItemsController < ApplicationController
  before_action :set_todo_list
  before_action :set_todo_item, only: %i[show edit update destroy]

  # GET /todolists/:todo_list_id/todoitems
  def index
  end

  # GET /todolists/:todo_list_id/todoitems/1
  def show
  end

  # GET /todolists/:todo_list_id/todoitems/new
  def new
    @todo_item = @todo_list.todo_items.build
  end

  # GET /todolists/:todo_list_id/todoitems/1/edit
  def edit
  end

  # POST /todolists/:todo_list_id/todoitems
  def create
    @todo_item = @todo_list.todo_items.build(todo_item_params)

    if @todo_item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todo_list_todo_items_path(@todo_list), notice: 'Todo item was successfully created.' }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /todolists/:todo_list_id/todoitems/1
  def update
    if @todo_item.update(todo_item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todo_list_todo_items_path(@todo_list), notice: 'Todo item was successfully updated.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /todolists/:todo_list_id/todoitems/1
  def destroy
    @todo_item.destroy!
    @todo_items = @todo_list.todo_items.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to todo_list_todo_items_path(@todo_list), notice: 'Todo item was successfully destroyed.' }
    end
  end

  # PATCH /todolists/:todo_list_id/todoitems/check_all
  def check_all
    @todo_list.todo_items.update_all(complete: true)
    @todo_items = @todo_list.todo_items.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to todo_list_todo_items_path(@todo_list) }
    end
  end

  private

  def set_todo_list
    @todo_list = TodoList.find(params[:todo_list_id])
  end

  def set_todo_item
    @todo_item = @todo_list.todo_items.find(params[:id])
  end

  def todo_item_params
    params.require(:todo_item).permit(:title, :complete)
  end
end
