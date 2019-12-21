require 'logger'
require 'async/websocket'
require 'async/websocket/adapters/rack'
require 'rack/protection'

APP_LOGGER = Logger.new(STDOUT)

module AsyncCable
  class Connection < Async::WebSocket::Connection
    def send_command(message)
      APP_LOGGER.info { "AsyncCable::Connection#send_command message=#{message.inspect}" }

      write(message)
      flush
    end

    def handle_command(message)
      APP_LOGGER.info { "AsyncCable::Connection#handle_command message=#{message.inspect}" }

      send_command(thanks: true, for: message)
    end

    def handle_open
      APP_LOGGER.info { "AsyncCable::Connection#handle_open." }
    end

    def handle_close(clean, code = nil)
      APP_LOGGER.info { "AsyncCable::Connection#handle_close clean=#{clean} code=#{code}" }
      close
    end
  end

  class Server
    def initialize(connection_class:)
      @connection_class = connection_class
    end

    def call(env)
      Async::WebSocket::Adapters::Rack.open(env, handler: @connection_class) do |connection|
        connection.handle_open

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
  use Rack::Session::Cookie, key: 'falcon-test.rack.session', secret: '12345'
  use Rack::Protection::SessionHijacking
  # use Rack::Protection::CookieTossing # break websocket

  map '/' do
    # use Rack::Protection::PathTraversal
    use Rack::CommonLogger, APP_LOGGER
    use Rack::Static, urls: %w(/assets /index.html), root: File.join(__dir__, 'public')
    not_found = proc do |env|
      APP_LOGGER.debug { "file #{env['REQUEST_PATH']} not found" }
      [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
    end
    run not_found
  end

  map '/cable' do
    use Rack::CommonLogger, APP_LOGGER
    run AsyncCable::Server.new(connection_class: AsyncCable::Connection)
  end
end

run app
