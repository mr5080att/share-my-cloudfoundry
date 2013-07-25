class UsersController < ApplicationController

  ##
  # Creates a new User and assigns an Organization and Space to the user
  #
  def create
    user_email = get_user_email

    # Create User
    user_random_password = SecureRandom.urlsafe_base64(8)
    begin
      user = User.new.create(user_email, user_random_password)
    rescue CFoundry::UAAError => e
      user = nil if e.message =~ /scim_resource_already_exists/
    end

    if user
      if Figaro.env.respond_to?(:cf_organization)
        organization = Organization.new.get(Figaro.env.cf_organization)
      else
        user_prefix = '0'
        organization_name = user_email.split('@')[0]
        begin
          organization = Organization.new.create(organization_name)
        rescue CFoundry::OrganizationNameTaken
          organization_name = user_email.split('@')[0] + user_prefix.succ!
          retry
        end
      end

      # Add Users and Roles to the Organization
      Organization.new.add_user(organization, user)
      Organization.new.assign_roles(organization, user, organization_roles) if organization_roles.any?

      # Create Space
      space = Space.new.create('development', organization, user)

      # Fill instance vars
      @user_email = user_email
      @user_password = user_random_password
      @organization_name = organization.name
      @space_name = space.name
    end

    respond_to do |format|
      format.html { render action: 'show' }
    end
  end

  private

  ##
  # Retrieves the User email
  #
  # @return [String] User email
  def get_user_email
    return params['email'] unless auth_hash

    case auth_hash.provider
      when 'twitter'
        auth_hash.info.nickname
      else
        auth_hash.info.email
    end
  end

  ##
  # Retrieves the Roles to assign to Users in an Organization
  #
  # @return [Array<String>] Arrays of roles to assign to users in an organization
  def organization_roles
    roles = []

    if Figaro.env.respond_to?(:cf_organization_add_manager) && Figaro.env.cf_organization_add_manager == 'true'
      roles << 'manager'
    end

    if Figaro.env.respond_to?(:cf_organization_add_billing_manager) && Figaro.env.cf_organization_add_billing_manager == 'true'
      roles << 'billing_manager'
    end

    if Figaro.env.respond_to?(:cf_organization_add_auditor) && Figaro.env.cf_organization_add_auditor == 'true'
      roles << 'auditor'
    end

    roles
  end

  ##
  # Returns OmniAuth Authentication Hash
  #
  # @return [Hash] OmniAuth Authentication Hash
  def auth_hash
    request.env['omniauth.auth']
  end
end
