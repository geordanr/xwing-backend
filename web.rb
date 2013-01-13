require 'time'

require 'sinatra/base'
require 'haml'

require 'omniauth'
require 'omniauth-google-oauth2'
require 'omniauth-facebook'

PROVIDERS = {
    :google_oauth2 => [ ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'], {access_type: 'online', approval_prompt: ''} ],
    :facebook => [ ENV['FACEBOOK_KEY'], ENV['FACEBOOK_SECRET'] ],
}

class OAuthDemo < Sinatra::Base
    use Rack::Session::Cookie
    use OmniAuth::Builder do
        PROVIDERS.each do |provider_name, provider_args|
            provider provider_name, *provider_args
        end
    end
    set :session_secret, ENV['SESSION_SECRET']

    get '/' do
        @time = Time.now
        @providers = PROVIDERS.keys
        haml :index
    end

    # Support both GET and POST for callbacks
    %w(get post).each do |method|
        send(method, "/auth/:provider/callback") do
            session[:u] = "#{env['omniauth.auth']['provider']}-#{env['omniauth.auth']['uid']}"
            redirect to('/protected')
        end
    end

    get '/auth/failure' do
        'Authentication failed'
    end

    get '/protected' do
        if session.has_key? :u
            "It's a secret to everyone!"
        else
            redirect to('/')
        end
    end
end
