require 'time'

require 'sinatra/base'
require 'haml'

require 'omniauth'
require 'omniauth-google-oauth2'

class OAuthDemo < Sinatra::Base
    use Rack::Session::Cookie
    use OmniAuth::Builder do
        provider :google_oauth2, ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET'], {access_type: 'online', approval_prompt: ''}
    end

    get '/' do
        @time = Time.now
        haml :index
    end

    # Support both GET and POST for callbacks
    %w(get post).each do |method|
        send(method, "/auth/:provider/callback") do
            env['omniauth.auth'] # => OmniAuth::AuthHash
        end
    end

    get '/auth/failure' do
        'Authentication failed'
    end

    get '/protected' do
        "It's a secret to everyone!"
    end
end
