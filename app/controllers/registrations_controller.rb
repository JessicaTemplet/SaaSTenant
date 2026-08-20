class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    @user.role = Current.tenant.users.exists? ? "member" : "owner" # first user owns the tenant

    if @user.save
      start_new_session_for @user
      redirect_to after_authentication_url, notice: "Welcome!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
