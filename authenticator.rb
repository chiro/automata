
require_relative 'lib/conf'
require 'rack/auth/digest/md5'
require 'digest/md5'
require 'webrick'

# Rack middleware to authenticate users
class Authenticator
  def initialize(app)
    @app = app
    @conf = Conf.new
  end

  def call(env)
    if env['PATH_INFO'] =~ /^\/account/
      md5 = Rack::Auth::Digest::MD5.new(
        @app,
        realm: @conf[:master, :authn_account, :realm],
        opaque: '',
        passwords_hashed: true
      ) do |_|
        Digest::MD5.hexdigest([
          @conf[:master, :authn_account, :user],
          @conf[:master, :authn_account, :realm],
          @conf[:master, :authn_account, :passwd]
        ].join(':'))
      end
      return md5.call(env)
    elsif env['PATH_INFO'] =~ /^\/(admin|api|browse|post|record)/
      md5 = Rack::Auth::Digest::MD5.new(
        @app,
        realm: @conf[:master, :authn, :realm],
        opaque: '',
        passwords_hashed: true
      ) do |username|
        htdigest = WEBrick::HTTPAuth::Htdigest.new(@conf[:master, :authn, :htdigest])
        htdigest.get_passwd(@conf[:master, :authn, :realm], username, true)
      end
      return md5.call(env)
    end
    @app.call(env)
  end
end