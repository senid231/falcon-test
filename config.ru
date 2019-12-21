require 'logger'
require 'async/websocket'
require 'async/websocket/adapters/rack'
require 'rack/protection'
require 'json'

APP_LOGGER = Logger.new(STDOUT)

SUBSCRIBERS = {}

module AsyncCable
  class Connection < Async::WebSocket::Connection
    def self.broadcast(data, except: [], only: [])
      APP_LOGGER.info { "AsyncCable::Connection.broadcast data=#{data.inspect}" }

      list = SUBSCRIBERS
      list = list.reject { |identifier, _| except.include?(identifier) } unless except.empty?
      list = list.reject { |identifier, _| !only.include?(identifier) } unless only.empty?

      list.each { |_, conn| conn.send_command(data) }
    end

    attr_reader :identifier

    def send_command(data)
      APP_LOGGER.info { "AsyncCable::Connection#send_command identifier=#{identifier} data=#{data.inspect}" }

      write(data)
      flush
    end

    def handle_command(data)
      APP_LOGGER.info { "AsyncCable::Connection#handle_command identifier=#{identifier} data=#{data.inspect}" }

      send_command(message: "message received", who: '<Server>')
      payload = { message: data[:message], who: identifier }
      self.class.broadcast(payload, except: [identifier])
    end

    def handle_open(env)
      user_id = env['rack.session']['user_id']

      if user_id.nil?
        APP_LOGGER.info { "AsyncCable::Connection#handle_open unauthorized" }
        send_close 1401, 'unauthorized'
        return
      end

      @identifier = "user_#{user_id}"
      SUBSCRIBERS[identifier] = self
      APP_LOGGER.info { "AsyncCable::Connection#handle_open identifier=#{identifier}" }

      payload = { message: "#{identifier} has joined", who: '<Server>' }
      self.class.broadcast(payload)
    end

    def handle_close(clean, code = nil)
      APP_LOGGER.info { "AsyncCable::Connection#handle_close identifier=#{identifier} clean=#{clean} code=#{code}" }
      SUBSCRIBERS.delete(identifier) if identifier
      close
      payload = { message: "#{identifier} has left", who: '<Server>' }
      self.class.broadcast(payload)
    end
  end

  class Server
    def initialize(connection_class:)
      @connection_class = connection_class
    end

    def call(env)
      Async::WebSocket::Adapters::Rack.open(env, handler: @connection_class) do |connection|
        connection.handle_open(env)

        while (data = connection.read)
          connection.handle_command(data)
        end
      rescue Protocol::WebSocket::ClosedError => error
        APP_LOGGER.info { "AsyncCable::Server ClosedError error=#{error.message}" }
        connection.handle_close(false, error.code)
      ensure
        APP_LOGGER.info { "AsyncCable::Server closed." }
        connection.handle_close(true, Protocol::WebSocket::Error::NO_ERROR)
      end or [200, {}, ['Hello World']]
    end
  end
end

Falcon::Adapters::Output.class_eval do
  def call(stream)
    @body.call(stream)
  end
end

app = Rack::Builder.new do
  use Rack::CommonLogger, APP_LOGGER
  use Rack::Session::Cookie, key: 'falcon-test.rack.session', secret: '12345'
  use Rack::Protection::SessionHijacking

  map '/login' do
    login = proc do |env|
      APP_LOGGER.debug { "login as #{env['QUERY_STRING']}" }
      user_id = env['QUERY_STRING']
      env['rack.session']['user_id'] = user_id
      [201, { 'Content-Type' => 'application/json' }, [JSON.generate(user_id: user_id)]]
    end
    run login
  end

  map '/logout' do
    logout = proc do |env|
      APP_LOGGER.debug { "logout as #{env['rack.session']['user_id']}" }
      env['rack.session'].delete('user_id')
      [204, { 'Content-Type' => 'application/json' }, []]
    end
    run logout
  end

  map '/' do
    use Rack::Protection::PathTraversal
    use Rack::Static, urls: %w(/assets /index.html), root: File.join(__dir__, 'public')
    not_found = proc do |env|
      APP_LOGGER.debug { "file #{env['REQUEST_PATH']} not found" }
      [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
    end
    run not_found
  end

  map '/cable' do
    run AsyncCable::Server.new(connection_class: AsyncCable::Connection)
  end
end

run app
