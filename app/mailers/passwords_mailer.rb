class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    @tenant = user.tenant
    mail subject: "Reset your password", to: user.email_address
  end
end
