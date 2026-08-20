class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Try again later." }

  def new
  end

  def create
    # `User` is already scoped to Current.tenant via TenantScoped, so this
    # can never authenticate a user from a different tenant even if two
    # tenants share the same email address.
    if (user = User.find_by(email_address: params[:email_address])) && user.authenticate(params[:password])
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "Invalid email address or password."
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path
  end
end
