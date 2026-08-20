class DocumentsController < ApplicationController
  def show
    @document = Current.tenant.documents.find(params[:id])
  end
end
