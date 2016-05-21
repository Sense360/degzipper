require 'degzipper'
require 'json'
require 'rack'
require 'zlib'

RSpec.describe Degzipper::Middleware do
  def gzip(content)
    string_io = StringIO.new

    gz = Zlib::GzipWriter.new(string_io)
    gz.write content
    gz.close

    string_io.string
  end

  let(:middleware) do
    Degzipper::Middleware.new(-> (env) do
      req = Rack::Request.new(env)

      body = JSON.dump(
          body:             req.body.read,
          content_encoding: env['HTTP_CONTENT_ENCODING'],
          length:           req.content_length.to_i
      )

      [200, {}, [body]]
    end)
  end

  it 'passes through a non-gzipped request body' do
    _, _, body = middleware.call(Rack::MockRequest.env_for(
        '/',
        method: 'POST',
        input:  'hello'
    ))

    parsed_body = JSON.parse(body.first)

    expect(parsed_body).to eq(
                               'body'             => 'hello',
                               'content_encoding' => nil,
                               'length'           => 5
                           )
  end

  it 'extracts a gzipped request body' do
    _, _, body = middleware.call(Rack::MockRequest.env_for(
        '/',
        method:                 'POST',
        input:                  gzip('hello'),
        'HTTP_CONTENT_ENCODING' => 'gzip'
    ))

    parsed_body = JSON.parse(body.first)

    expect(parsed_body).to eq(
                               'body'             => 'hello',
                               'content_encoding' => nil,
                               'length'           => 5
                           )
  end

  it 'sets the correct content length for UTF-8 content' do
    _, _, body = middleware.call(Rack::MockRequest.env_for(
        '/',
        method:                 'POST',
        input:                  gzip('你好'),
        'HTTP_CONTENT_ENCODING' => 'gzip'
    ))

    parsed_body = JSON.parse(body.first)

    expect(parsed_body).to eq(
                               'body'             => '你好',
                               'content_encoding' => nil,
                               'length'           => 6
                           )
  end

  it "passes an empty body if invalid gzip data" do
    _, _, body = middleware.call(Rack::MockRequest.env_for(
        '/',
        method:                 'POST',
        input:                  'NOT GZIP BODY',
        'HTTP_CONTENT_ENCODING' => 'gzip'
    ))

    parsed_body = JSON.parse(body.first)

    expect(parsed_body).to eq(
                               'body'             => '',
                               'content_encoding' => nil,
                               'length'           => 0
                           )
  end

  let(:middleware_nojson) do
    Degzipper::Middleware.new(-> (env) do
      req = Rack::Request.new(env)

      body = {
          body:             req.body.read,
          content_encoding: env['HTTP_CONTENT_ENCODING'],
          length:           req.content_length.to_i
      }

      [200, {}, [body]]
    end)
  end

  it "skips paths that are excluded" do
    Degzipper::Middleware::EXCLUDED_PATHS << '/exclude_path'
    input      = gzip('hello')
    _, _, body = middleware_nojson.call(Rack::MockRequest.env_for(
        '/exclude_path',
        method:                 'POST',
        input:                  input,
        'HTTP_CONTENT_ENCODING' => 'gzip'
    ))

    expect(body).to eq([{
                            body:             input,
                            content_encoding: 'gzip',
                            length:           25
                        }])
  end
end
