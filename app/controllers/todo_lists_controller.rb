class TodoListsController < ApplicationController
  before_action :set_todo_list, only: %i[show edit update destroy]

  # GET /todolists
  def index
    @todo_lists = TodoList.all
    @todo_list = @todo_lists.first
    @new_todo_list = TodoList.new
  end

  # GET /todolists/1
  def show
  end

  # GET /todolists/new
  def new
    @todo_list = TodoList.new
  end

  # GET /todolists/1/edit
  def edit
  end

  # POST /todolists
  def create
    @todo_list = TodoList.new(todo_list_params)

    if @todo_list.save
      @todo_lists = TodoList.all
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todo_lists_path, notice: 'Todo list was successfully created.' }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /todolists/1
  def update
    if @todo_list.update(todo_list_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to todo_lists_path, notice: 'Todo list was successfully updated.' }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /todolists/1
  def destroy
    @todo_list.destroy!
    @todo_lists = TodoList.all

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to todo_lists_path, notice: 'Todo list was successfully destroyed.' }
    end
  end

  private

  def set_todo_list
    @todo_list = TodoList.find(params[:id])
  end

  def todo_list_params
    params.require(:todo_list).permit(:name)
  end
end
