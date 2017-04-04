require 'time'

require 'sinatra/base'
require 'rack/cors'
require 'haml'
require 'couchrest'
require 'json'
require 'uuid'

require 'omniauth'
require 'omniauth-google-oauth2'
require 'omniauth-facebook'
require 'omniauth-twitter'

PROVIDERS = {
    :google_oauth2 => [ ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'], {access_type: 'online', approval_prompt: ''} ],
    :facebook => [ ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'] ],
    :twitter => [ ENV['TWITTER_KEY'], ENV['TWITTER_SECRET'] ],
}

VALID_SETTINGS = [
    'language',
    'hugeShipMovedWarningSeen',
]

INTERESTING_HEADERS = [
    'HTTP_ACCEPT_LANGUAGE',
]

class XWingSquadDatabase < Sinatra::Base
    # Config

    configure do
        enable :method_override

        # https://github.com/sinatra/sinatra/issues/518
        set :protection, :except => :json_csrf
    end

    configure :production do
        set :db, CouchRest.database(ENV['CLOUDANT_URL'])
    end

    configure :development do
        begin
            File.open('dev_cloudant.url') do |f|
                set :db, CouchRest.database(f.read.strip)
            end
        rescue
            set :db, CouchRest.database(ENV['CLOUDANT_DEV_URL'])
        end
    end

    # Middleware

    use Rack::Session::Cookie, :secret => ENV['SESSION_SECRET']

    use OmniAuth::Builder do
        PROVIDERS.each do |provider_name, provider_args|
            provider provider_name, *provider_args
        end
    end

    use Rack::Cors do
        allow do
            origins ENV['ALLOWED_ORIGINS']
            resource '*', :credentials => true,
                :methods => [ :get, :post, :put, :delete ],
                :headers => :any
        end
    end

    # Auth stuff

    helpers do
        def require_authentication()
            if session.has_key? :u
                begin
                    user_doc = settings.db.get session[:u]
                    if user_doc.nil?
                        puts "User #{session[:u].inspect} not found"
                        halt 401, 'Invalid user; re-authenticate with OAuth'
                    end
                rescue => e
                    puts "Could not get user doc: #{e}"
                end
                env['xwing.user'] = User.fromDoc(user_doc)
            else
                halt 401, 'Authentication via OAuth required'
            end
        end

        def name_is_available?(name)
            settings.db.view('squads/byUserName', { :key => [ env['xwing.user']['_id'], name ] })['rows'].empty?
        end

        def json(data)
            content_type :json
            if data.instance_of? Hash
                data.to_json
            else
                { :data => data }.to_json
            end
        end

        def get_collection()
            collection = Collection.new(env['xwing.user']['_id'], {}, {})

            begin
                collection_doc = settings.db.get(collection['_id'])
                if collection_doc.nil?
                    # If no collection already exists for the logged in user, create a new empty one.
                    res = settings.db.save_doc(collection)
                    collection_doc = settings.db.get(res['id'])
                end
            rescue => e
                puts "Error getting collection for user #{env['xwing.user']['_id']}: #{e}"
                halt 500
            end

            Collection.fromDoc(collection_doc)
        end
    end

    before '/squads/*' do
        require_authentication
    end

    # Support both GET and POST for callbacks
    %w(get post).each do |method|
        send(method, "/auth/:provider/callback") do
            user = User.new(env['omniauth.auth']['provider'], env['omniauth.auth']['uid'])
            # Check if user exists
            begin
                user_doc = settings.db.get user['_id']
                session[:u] = user_doc['_id']
            rescue
                # If not, add it
                res = settings.db.save_doc(user)
                session[:u] = res['id']
            end

            haml :auth_success
        end
    end

    get '/auth/failure' do
        halt 403, 'Authentication failed'
    end

    get '/auth/logout' do
        session.delete :u
        json :message => 'Logged out; reauthenticate with OAuth'
    end

    # App routes

    get '/' do
        json :welcome => 'Yet Another X-Wing Database Backend'
    end

    get '/headers' do
        data = {}
        INTERESTING_HEADERS.each do |header|
            data[header] = request.env[header]
        end
        json :headers => data
    end

    get '/settings' do
        session[:settings] = {} if session[:settings].nil?
        settings = session[:settings]
        json :settings => settings
    end

    put '/settings' do
        session[:settings] = {} if session[:settings].nil?
        settings = session[:settings]
        settings_set = {}
        params.each_pair do |setting, value|
            if VALID_SETTINGS.member? setting
                settings[setting] = settings_set[setting] = value
            end
        end
        json :set => settings_set
    end

    delete '/settings/:setting' do
        setting = params[:setting]
        if VALID_SETTINGS.member? setting
            session[:settings] = {} if session[:settings].nil?
            settings = session[:settings]
            settings.delete setting if settings.has_key? setting
        end
        json :deleted => setting
    end

    get '/methods' do
        json :methods => PROVIDERS.keys
    end

    # Unprotected; everyone can view the full list
    get '/all' do
        out = {
            'Rebel Alliance' => [],
            'Galactic Empire' => [],
            'Scum and Villainy' => [],
        }
        settings.db.view('squads/list', { :reduce => false })['rows'].each do |row|
            _, faction, name = row['key']
            out[faction].push({
                :id => row['id'],
                :name => name,
                :serialized => row['value']['serialized'] || nil,
                :additional_data => row['value']['additional_data'] || nil,
            })
        end
        json out
    end

    get '/squads/list' do
        out = {
            'Rebel Alliance' => [],
            'Galactic Empire' => [],
            'Scum and Villainy' => [],
        }
        settings.db.view('squads/list', { :reduce => false, :startkey => [ env['xwing.user']['_id'] ], :endkey => [ env['xwing.user']['_id'], {}, {} ] })['rows'].each do |row|
            _, faction, name = row['key']
            out[faction].push({
                :id => row['id'],
                :name => name,
                :serialized => row['value']['serialized'] || nil,
                :additional_data => row['value']['additional_data'] || nil,
            })
        end
        json out
    end

    put '/squads/new' do
        name = params[:name].strip
        if name_is_available? name
            new_squad = Squad.new(env['xwing.user']['_id'], params[:serialized].strip, name, params[:faction].strip, params[:additional_data])
            begin
                res = settings.db.save_doc(new_squad)
                json :id => res['id'], :success => true, :error => nil
            rescue
                json :id => nil, :success => false, :error => 'Something bad happened saving that squad, try again later'
            end
        else
            json :id => nil, :success => false, :error => 'You already have a squad with that name'
        end
    end

    delete '/squads/:id' do
        id = params[:id]
        begin
            squad_doc = settings.db.get(id)
        rescue
            json :id => nil, :success => false, :error => 'Something bad happened fetching that squad, try again later'
        end
        if squad_doc['user_id'] != env['xwing.user']['_id']
            json :id => nil, :success => false, :error => "You don't own that squad"
        else
            begin
                squad_doc.destroy
                json :success => true, :error => nil
            rescue
                json :id => nil, :success => false, :error => 'Something bad happened deleting that squad, try again later'
            end
        end
    end

    post '/squads/namecheck' do
        name = params[:name].strip
        json :available => name_is_available?(name)
    end

    post '/squads/:id' do
        id = params[:id].strip
        begin
            squad = Squad.fromDoc(settings.db.get(id))
        rescue
            json :id => nil, :success => false, :error => 'Something bad happened fetching that squad, try again later'
        end
        if squad['user_id'] != env['xwing.user']['_id']
            json :id => nil, :success => false, :error => "You don't own that squad"
        else
            name = params[:name].strip
            if name != squad['name'] and not name_is_available? name
                json :id => nil, :success => false, :error => 'You already have a squad with that name'
            else
                squad.update({
                    'name' => name,
                    'serialized' => params[:serialized].strip,
                    'faction' => params[:faction].strip,
                    'additional_data' => params[:additional_data],
                })
                begin
                    settings.db.save_doc(squad)
                    json :id => squad['_id'], :success => true, :error => nil
                rescue
                    json :id => nil, :success => false, :error => 'Something bad happened saving that squad, try again later'
                end
            end
        end
    end

    get '/ping' do
        require_authentication
        json :success => true
    end

    get '/collection' do
        require_authentication

        collection = get_collection

        json :collection => {
            'expansions' => collection['expansions'],
            'singletons' => collection['singletons']
        }
    end

    post '/collection' do
        require_authentication

        collection = get_collection
        collection['expansions'] = params[:expansions]
        collection['singletons'] = params[:singletons]
        begin
            _ = settings.db.save_doc(collection)
            json :success => true, :error => nil
        rescue => e
            puts "Error saving collection for user #{env['xwing.user']['_id']}: #{e}"
            halt 500
        end
    end

    # Demo

    get '/protected' do
        require_authentication
        "It's a secret to everyone!"
    end

    get '/haml' do
        haml :auth_success
    end
end

class User < Hash
    def initialize(provider, uid)
        self['_id'] = "user-#{provider}-#{uid}"
        self['type'] = 'user'
    end

    def self.fromDoc(doc)
        new_obj = self.new(nil, nil)
        new_obj.update(doc)
        new_obj
    end

    def to_s
        "#<User id=#{self['_id']}>"
    end
end

class Squad < Hash
    def initialize(user_id, serialized_str, name, faction, additional_data)
        self['_id'] = "squad_#{UUID.generate}"
        self['type'] = 'squad'
        self['user_id'] = user_id
        self['serialized'] = serialized_str
        self['name'] = name
        self['faction'] = faction
        if additional_data.instance_of? Hash
            self['additional_data'] = additional_data.to_hash
        end
    end

    def self.fromDoc(doc)
        new_obj = self.new(nil, nil, nil, nil, nil)
        new_obj.update(doc)
        new_obj
    end

    def to_s
        "#<Squad user_id=#{self['_id']}, faction=#{self['faction']}, name=#{self['name']}>"
    end
end

class Collection < Hash
    def initialize(user_id, expansions, singletons)
        self['_id'] = "collection_#{user_id}"
        self['type'] = 'collection'
        self['user_id'] = user_id
        self['expansions'] = expansions
        self['singletons'] = singletons
    end

    def self.fromDoc(doc)
        new_obj = self.new(nil, nil, nil)
        new_obj.update(doc)
        new_obj
    end

    def to_s
        "#<Collection id=#{self['_id']}, user_id=#{self['user_id']}, expansions=#{self['expansions']}, singletons=#{self['singletons']}>"
    end
end
