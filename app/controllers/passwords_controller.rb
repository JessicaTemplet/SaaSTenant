class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]

  def new
  end

  def create
    if (user = User.find_by(email_address: params[:email_address]))
      PasswordsMailer.reset(user).deliver_later
    end
    # Always show the same message, regardless of whether the email
    # matched a user — don't leak account existence.
    redirect_to new_session_path, notice: "Check your email for reset instructions."
  end

  def edit
  end

  def update
    if @user.update(password_params)
      redirect_to new_session_path, notice: "Password reset. Please sign in."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_user_by_token
    @user = User.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to new_password_path, alert: "That password reset link is invalid or has expired."
  end

  def password_params
    params.permit(:password, :password_confirmation)
  end
end
