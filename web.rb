require 'digest'
require 'time'

require 'sinatra/base'
require 'sinatra/json'
require 'haml'
require 'couchrest'
require 'json'
require 'uuid'

require 'omniauth'
require 'omniauth-google-oauth2'
require 'omniauth-facebook'

PROVIDERS = {
    :google_oauth2 => [ ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'], {access_type: 'online', approval_prompt: ''} ],
    :facebook => [ ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'] ],
}

class OAuthDemo < Sinatra::Base
    # Helpers
    helpers Sinatra::JSON

    # Middleware

    use Rack::Session::Cookie
    use OmniAuth::Builder do
        PROVIDERS.each do |provider_name, provider_args|
            provider provider_name, *provider_args
        end
    end

    # Config

    configure do
        set :session_secret, ENV['SESSION_SECRET']
        set :method_override, true
        set :uuid, UUID.new
    end

    configure :production do
        set :db, CouchRest.database(ENV['CLOUDANT_URL'])
    end

    configure :development do
        set :db, CouchRest.database(ENV['CLOUDANT_DEV_URL'])
        #File.open('dev_cloudant.url') do |f|
        #    set :db, CouchRest.database(f.read.strip)
        #end
    end

    # Auth stuff

    helpers do
        def require_authentication()
            if session.has_key? :u
                halt 403, 'Authentication via OAuth required'
            end
        end
    end

    before '/squads/*' do
        require_authentication
    end

    # Support both GET and POST for callbacks
    %w(get post).each do |method|
        send(method, "/auth/:provider/callback") do
            userid = "user_#{env['omniauth.auth']['provider']}-#{env['omniauth.auth']['uid']}"
            # Check if user exists
            db = settings.db
            begin
                user_doc = db.get userid
            rescue RestClient::ResourceNotFound
                # If not, add it
                user_doc = db.save_doc(User.new(userid))
            end
            
            session[:u] = Digest::SHA1.hexdigest("#{userid}#{ENV['USERID_SECRET']}")
            redirect to('/protected')
        end
    end

    get '/auth/failure' do
        halt 403, 'Authentication failed'
    end

    get '/auth/logout' do
        session.delete :u
        'You have been logged out.'
    end

    # App routes

    get '/' do
        @time = Time.now
        @providers = PROVIDERS.keys
        haml :index
    end

    get '/methods' do
        json PROVIDERS.keys
    end

    get '/squads/list' do
    end

    get '/squads/listAll' do
    end

    put '/squads/new' do
    end

    post '/squads/:id' do
        id = params[:id]
    end

    delete '/squads/:id' do
        id = params[:id]
    end

    get '/whoami' do
        require_authentication
        json :id => session[:u]
    end

    # Demo

    get '/protected' do
        if session.has_key? :u
            "It's a secret to everyone!"
        else
            redirect to('/')
        end
    end
end

class User < Hash
    def initialize(userid)
        self['id'] = "user_#{userid}"
        self['type'] = 'user'
    end
end

class Squad < Hash
    def initialize(serialized_str, name, additional_data)
        self['id'] = "squad_#{settings.get(:uuid).generate}"
        self['type'] = 'squad'
        self['name'] = name
        if additional_data.instance_of? Hash
            self['additional_data'] = additional_data.to_hash
        end
    end
end
