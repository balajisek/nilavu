require 'json'

class MarketplacesController < ApplicationController
  respond_to :js
  include MarketplaceHelper
  include AppsHelper
  ##
  ## index page get all marketplace items from storage(we use riak) using megam_gateway
  ## and show the items in order of category
  ##
  def index
    if current_user_verify
      mkp = get_marketplaces

      @mkp_collection = mkp[:mkp_collection]
      if @mkp_collection.class == Megam::Error
        redirect_to main_dashboards_path, :gflash => { :warning => { :value => "API server may be down. Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/", :target => "_blank"}.", :sticky => false, :nodom_wrap => true } }
      else
        @categories=[]
        @order=[]
        @order = @mkp_collection.map {|c|
      c.name
      }
        @order = @order.sort_by {|elt| ary = elt.split("-").map(&:to_i); ary[0] + ary[1]}
        @categories = @mkp_collection.map {|c| c.appdetails[:category]}
        @categories = @categories.uniq

      end
    else
      redirect_to signin_path
    end
  end

  ##
  ## to show the selected marketplace item
  ##
  def show
    if current_user_verify
      @pro_name = params[:id].split("-")
      @apps = get_apps
      @mkp = GetMarketplaceApp.perform(force_api[:email], force_api[:api_key], params[:id])
      if @mkp.class == Megam::Error
        redirect_to main_dashboards_path, :gflash => { :warning => { :value => "API server may be down. Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/", :target => "_blank"}.", :sticky => false, :nodom_wrap => true } }
      else
        @mkp = @mkp.lookup(params[:id])
        @predef_name = get_predef_name(@pro_name[3].downcase)
        @deps_scm = get_deps_scm(@pro_name[3].downcase)
        @my_apps = []

        @type = get_type(@pro_name[3].downcase)
        @version_order=[]
        @version_order = @mkp.plans.map {|c| c["version"]}
        @version_order = @version_order.sort

        @ssh_keys_collection = ListSshKeys.perform(force_api[:email], force_api[:api_key])
        logger.debug "--> #{self.class} : listed sshkeys"

        if @ssh_keys_collection.class != Megam::Error
          @ssh_keys = []
          ssh_keys = []
          @ssh_keys_collection.each do |sshkey|
            ssh_keys << {:name => sshkey.name, :created_at => sshkey.created_at.to_time.to_formatted_s(:rfc822)}
          end
          @ssh_keys = ssh_keys.sort_by {|vn| vn[:created_at]}
        end

        respond_to do |format|
          format.js {
            respond_with(@mkp, @version_order, @type, @ssh_keys, :layout => !request.xhr? )
          }
        end
      end
    else
      redirect_to signin_path
    end
  end

  ##
  ## get all assemblies(it means applications) for that user launched and
  ## list the applications in dashboard
  ##
  def get_apps
    apps = []
    if current_user_verify
      @user_id = current_user["email"]
      @assemblies = ListAssemblies.perform(force_api[:email],force_api[:api_key])
      @service_counter = 0
      @app_counter = 0
      if @assemblies != nil
        @assemblies.each do |asm|
          if asm.class != Megam:: Error
            asm.assemblies.each do |assembly|
              if assembly != nil
                if assembly[0].class != Megam::Error
                  assembly[0].components.each do |com|
                    if com != nil
                      com.each do |c|
                        com_type = c.tosca_type.split(".")
                        ctype = get_type(com_type[2])
                        if ctype == "APP" && com[0].related_components == ""
                          apps << {"name" => assembly[0].name + "." + assembly[0].components[0][0].inputs[:domain] + "/" + com[0].name, "aid" => assembly[0].id, "cid" => assembly[0].components[0][0].id }
                        end
                      end
                    end
                  end
                  assembly[0].components.each do |com|
                    if com != nil
                      com.each do |c|
                        com_type = c.tosca_type.split(".")
                        ctype = get_type(com_type[2])
                        if ctype == "APP"
                          @app_counter = @app_counter + 1
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    else
      redirect_to signin_path
    end
    apps
  end

=begin
def authorize_scm
logger.debug "CloudBooks:authorize_scm, entry"
auth_token = request.env['omniauth.auth']['credentials']['token']
github = Github.new oauth_token: auth_token
git_array = github.repos.all.collect { |repo| repo.clone_url }
@repos = git_array
render :template => "apps/new", :locals => {:repos => @repos}

#session[:info] = request.env['omniauth.auth']['credentials']
auth_token = request.env['omniauth.auth']['credentials']['token']
github = Github.new oauth_token: auth_token
git_array = github.repos.all.collect { |repo| repo.clone_url }
@repos = git_array

# @repos
end

=end

  ##
  ## after finish the github authentication the callback url comes this method
  ## this function parse the request and get the github credentials
  ## and store that credentials to session
  ##
  def github_scm
    if current_user.nil?
      redirect_to :controller=>'sessions', :action=>'create'
    else
      @auth_token = request.env['omniauth.auth']['credentials']['token']
      session[:github] =  @auth_token
      session[:git_owner] = request.env['omniauth.auth']['extra']['raw_info']['login']
    end
  end

  ##
  ## this method collect all repositories for user using oauth token
  ##
  def github_sessions
    auth_id = params['id']
    github = Github.new oauth_token: auth_id
    git_array = github.repos.all.collect { |repo| repo.clone_url }
    @repos = git_array
    respond_to do |format|
      format.js {
        respond_with(@repos, :layout => !request.xhr? )
      }
    end
  end

  ##
  ## get session data and sends to UI
  ##
  def github_sessions_data
    @tokens_gh = session[:github]
    render :text => @tokens_gh
  end

  def gogs
  end

  ##
  ## gogswindow html page method
  ##
  def gogswindow
  end

  ##
  ## get the repositories from session
  ##
  def gogs_sessions
    @repos = session[:gogs_repos]
    respond_to do |format|
      format.js {
        respond_with(@repos, :layout => !request.xhr? )
      }
    end
  end

  ##
  ## this function get the gogs token using username and password
  ## then list the repositories using oauth tokens.
  ##
  def gogs_return
    session[:gogs_owner] = params[:gogs_username]
    tokens = ListGogsTokens.perform(params[:gogs_username], params[:gogs_password])
    obj = JSON.parse(tokens)
    token = obj[0]["sha1"]
    session[:gogs_token] = token
    @gogs_repos = ListGogsRepo.perform(token)
    obj_repo = JSON.parse(@gogs_repos)
    @repos_arr = []
    obj_repo.each do |one_repo|
      @repos_arr << one_repo["clone_url"]
    end
    session[:gogs_repos] =  @repos_arr
  end

  ##
  ## user clicks the particular marketplace item then this controller collect the details of
  ## that selected item and show the contents
  ##
  def category_view
    mkp = get_marketplaces
    @mkp_collection = mkp[:mkp_collection]
    if @mkp_collection.class == Megam::Error
      redirect_to cloud_dashboards_path, :gflash => { :warning => { :value => "API server may be down. Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/", :target => "_blank"}.", :sticky => false, :nodom_wrap => true } }
    else
      @categories=[]
      @categories = @mkp_collection.map {|c| c.appdetails[:category]}
      @categories = @categories.uniq
      @category = params[:category]
      respond_to do |format|
        format.js {
          respond_with(@category, @mkp_collection, @categories, :layout => !request.xhr? )
        }
      end
    end
  end

  ##
  ## this controller collect all registered marketplace items from megam storage
  ##
  def get_marketplaces
    if current_user_verify
      mkp_collection = ListMarketPlaceApps.perform(force_api[:email], force_api[:api_key])
      {:mkp_collection => mkp_collection}
    else
      redirect_to signin_path
    end
  end

  ##
  ## when change the version of marketplace item then this controller change the contents of that item
  ##
  def changeversion
    if current_user_verify
      @pro_name = params[:id].split("-")
      @version = params[:version]
      @mkp = GetMarketplaceApp.perform(force_api[:email], force_api[:api_key], params[:id])
      if @mkp.class == Megam::Error
        redirect_to main_dashboards_path, :gflash => { :warning => { :value => "API server may be down. Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/", :target => "_blank"}.", :sticky => false, :nodom_wrap => true } }
      else
        @mkp = @mkp.lookup(params[:id])
        @type = get_type(@pro_name[3].downcase)
        respond_to do |format|
          format.js {
            respond_with(@mkp, @version, @type, :layout => !request.xhr? )
          }
        end
      end
    else
      redirect_to signin_path
    end
  end

  ##
  ## this controller launch the instances(which means virtual machines)
  ## this performs three types of condition operations for launching instances using sshkeys
  ##
  def instances_create
    if current_user_verify
      assembly_name = params[:name]
      version = params[:version]
      domain = params[:domain]
      cloud = params[:cloud]
      source = params[:source]
      type = params[:type].downcase
      sshoption = params[:sshoption]
      sshcreatename = params[:sshcreatename]
      sshuploadname = params[:sshuploadname]
      sshexistname = params[:sshexistname]

      dbname = nil
      dbpassword = nil

      combos = params[:combos]
      combo = combos.split("+")

      ttype = "tosca.web."
      appname = params[:appname]
      servicename = nil      
      
    end
  end

  ##
  ## this controller launch the starters pack(megam provide these packages)
  ##
  def starter_packs_create
    if current_user_verify
      assembly_name = params[:name]
      version = params[:version]
      domain = params[:domain]
      cloud = params[:cloud]
      source = params[:source]
      type = params[:type].downcase

      dbname = nil
      dbpassword = nil

      combos = params[:combos]

      combo = combos.split("+")
      puts combo.inspect

      appname = params[:appname]
      servicename = params[:servicename]

      predef = GetPredefCloud.perform(params[:cloud], force_api[:email], force_api[:api_key])
      if predef.class == Megam::Error
        @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
        respond_to do |format|
          format.js {
            respond_with(@err_msg, :layout => !request.xhr? )
          }
        end
      else
      # if predef[0].spec[:type_name] == "docker"
      # ttype = "tosca.docker."
      # else
        ttype = "tosca.web."
        #end

        options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword  }
        app_hash=MakeAssemblies.perform(options, force_api[:email], force_api[:api_key])
        @res = CreateAssemblies.perform(app_hash,force_api[:email], force_api[:api_key])
        if @res.class == Megam::Error
          @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
          respond_to do |format|
            format.js {
              respond_with(@err_msg, :layout => !request.xhr? )
            }
          end
        end
      end
    else
      redirect_to signin_path
    end
  end

  ##
  ## this controller launch the services
  ## it checks service is bind any of the applications, the service is bind to application then add the application name to inputs
  ##
  def app_boilers_create
    if current_user_verify
      assembly_name = params[:name]
      version = params[:version]
      domain = params[:domain]
      cloud = params[:cloud]
      source = params[:source]
      type = params[:type].downcase
      dbname = nil
      dbpassword = nil

      combos = params[:combos]
      combo = combos.split("+")

      servicename = params[:servicename]
      if params[:bindedAPP] != "" && params[:bindedAPP] != "select an APP"
        bindedAPP = params[:bindedAPP].split(":")
        appname = bindedAPP[0].split("/")[1]
      related_components = bindedAPP[0]
      else
        appname = nil
        related_components = nil
      end

      if type == "postgresql"
        dbname = current_user["email"]
        dbpassword = ('0'..'z').to_a.shuffle.first(8).join
      end

      predef = GetPredefCloud.perform(params[:cloud], force_api[:email], force_api[:api_key])
      if predef.class == Megam::Error
        @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
        respond_to do |format|
          format.js {
            respond_with(@err_msg, :layout => !request.xhr? )
          }
        end
      else
      #if predef[0].spec[:type_name] == "docker"
      #  ttype = "tosca.docker."
      #else
        ttype = "tosca.web."
        #end

        options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :related_components => related_components, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword  }
        app_hash=MakeAssemblies.perform(options, force_api[:email], force_api[:api_key])
        @res = CreateAssemblies.perform(app_hash,force_api[:email], force_api[:api_key])
        if @res.class == Megam::Error
          @res_msg = nil
          @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
          respond_to do |format|
            format.js {
              respond_with(@res_msg, @err_msg, :layout => !request.xhr? )
            }
          end
        else
          if params[:bindedAPP] != "" && params[:bindedAPP] != "select an APP"
            bindedAPP = params[:bindedAPP].split(":")
            get_assembly = GetAssemblyWithoutComponentCollection.perform(bindedAPP[1], force_api[:email], force_api[:api_key])
            if get_assembly.class == Megam::Error
              @res_msg = nil
              @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
              respond_to do |format|
                format.js {
                  respond_with(@res_msg, @err_msg, :layout => !request.xhr? )
                }
              end
            else
              get_component = GetComponent.perform(bindedAPP[2], force_api[:email], force_api[:api_key])
              if get_component.class == Megam::Error
                @res_msg = nil
                @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
                respond_to do |format|
                  format.js {
                    respond_with(@res_msg, @err_msg, :layout => !request.xhr? )
                  }
                end
              else
                relatedcomponent = assembly_name + "." + domain + "/" + servicename
                update_component_json = UpdateComponentJson.perform(get_component, relatedcomponent)
                update_component = UpdateComponent.perform(update_component_json, force_api[:email], force_api[:api_key])
                if update_component.class == Megam::Error
                  @res_msg = nil
                  @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
                  respond_to do |format|
                    format.js {
                      respond_with(@res_msg, @err_msg, :layout => !request.xhr? )
                    }
                  end
                else
                  update_json = UpdateAssemblyJson.perform(get_assembly, get_component)
                  update_assembly = UpdateAssembly.perform(update_json, force_api[:email], force_api[:api_key])
                  if update_assembly.class == Megam::Error
                    @res_msg = nil
                    @err_msg="Please contact #{ActionController::Base.helpers.link_to 'support !.', "http://support.megam.co/"}."
                    respond_to do |format|
                      format.js {
                        respond_with(@res_msg, @err_msg, :layout => !request.xhr? )
                      }
                    end
                  else
                    @err_msg = nil
                  end
                end
              end
            end
          end
        end
      end
      @res_msg = "success"
      @err_msg = nil
    else
      redirect_to signin_path
    end
  end

  ##
  ## this controller launch the addons
  ##
  def addons_create
    if current_user_verify
      assembly_name = params[:name]
      version = params[:version]
      domain = params[:domain]
      cloud = params[:cloud]
      source = params[:source]
      type = params[:type].downcase
      dbname = nil
      dbpassword = nil

      combos = params[:combos]
      combo = combos.split("+")

      ttype = "tosca.web."
      appname = params[:appname]
      servicename = nil

      options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword  }
      app_hash=MakeAssemblies.perform(options, force_api[:email], force_api[:api_key])
      @res = CreateAssemblies.perform(app_hash,force_api[:email], force_api[:api_key])
      if @res.class == Megam::Error
        @profile = "http://support.megam.co/"
        @err_msg= ActionController::Base.helpers.link_to 'Contact support', @profile
        respond_to do |format|
          format.js {
            respond_with(@err_msg, :layout => !request.xhr? )
          }
        end
      end
    else
      redirect_to signin_path
    end
  end

  ##
  ## byoc means bring your own code
  ## this option the users put their project from scm(github, gogs...)
  ## then launch the application to cloud
  ##
  def byoc_create
    assembly_name = params[:name]

    version = params[:version]
    domain = params[:domain]
    cloud = params[:cloud]
    #app_type = params[:byoc]
    source = params[:source]
    type = params[:byoc].downcase

    dbname = nil
    dbpassword = nil
    combo = []
    combo << params[:byoc].downcase

    ttype = "tosca.web."
    appname = params[:appname]
    servicename = nil

    if params[:scm_name] == "github"
      scmtoken =  session[:github]
      scmowner =  session[:git_owner]
    elsif params[:scm_name] == "gogs"
      scmtoken =  session[:gogs_token]
      scmowner =  session[:gogs_owner]
    else
      scmtoken =  ""
      scmowner =  ""
    end

    if params[:check_ci] == "true"
      options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword, :ci => true, :scm_name => params[:scm_name], :scm_token =>  scmtoken, :scm_owner => scmowner }
    else
    #options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword, :ci => false, :scm_name => params[:scm_name], :scm_token =>  scmtoken, :scm_owner => scmowner   }
      options = {:assembly_name => assembly_name, :appname => appname, :servicename => servicename, :component_version => version, :domain => domain, :cloud => cloud, :source => source, :ttype => ttype, :type => type, :combo => combo, :dbname => dbname, :dbpassword => dbpassword, :ci => true, :scm_name => params[:scm_name], :scm_token =>  scmtoken, :scm_owner => scmowner }
    end
    app_hash=MakeAssemblies.perform(options, force_api[:email], force_api[:api_key])
    @res = CreateAssemblies.perform(app_hash,force_api[:email], force_api[:api_key])
    if @res.class == Megam::Error
      @profile = "http://support.megam.co/"
      @err_msg= ActionController::Base.helpers.link_to 'Contact support', @profile
      respond_to do |format|
        format.js {
          respond_with(@err_msg, :layout => !request.xhr? )
        }
      end
    end
  end

end

