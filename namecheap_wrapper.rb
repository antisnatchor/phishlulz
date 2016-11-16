# author: @antisnatchor
# TODO -- NOTE this is not ready/finished, and it's using the NameCheap Sandbox API (not the production API)
# TODO -- I will make it work soon, or even better, send a pull request to finish what needs to be done :-)
require 'rubygems'
require 'nokogiri'
require 'rest-client'
require 'yaml'


class NameCheapWrapper

  def initialize
    loaded_config = "config.yaml"
    config = YAML.load_file(loaded_config)

    @APIUSER = config['registrar']['user']
    @APIKEY = config['registrar']['key']
    @ENDPOINT = config['registrar']['endpoint']
    @WHITELISTED_IP = config['registrar']['whitelisted_ip']
    @DEBUG = config['registrar']['debug']
  end


  # merge basic parameters with new params neeed for specific command
  def prepare_req(cmd, hash_items)
     params = {
         :ApiUser  => @APIUSER,
         :ApiKey   => @APIKEY,
         :UserName => @APIUSER,
         :ClientIP => @WHITELISTED_IP,
         :Command  => cmd
     }
     params = params.merge(hash_items) if hash_items != nil
     params
  end

  # send prepared request and returns response object (Nokogiri::XML)
  def send_req(cmd, method, cmd_input=nil)
    begin
      res = nil
      puts "[--- DEBUG ---] Requests parameters:\n#{cmd_input.inspect}" if @DEBUG

      if method == 'GET'
        res = RestClient.get "#{@ENDPOINT}", {:params => prepare_req(cmd, cmd_input)}
      elsif method == 'POST'
        res = RestClient.post "#{@ENDPOINT}", {:params => prepare_req(cmd, cmd_input)}
      else
        puts "Error: Method not Allowed."
      end

      puts "[--- DEBUG ---] Raw Response:\n#{cmd_input.inspect}" if @DEBUG


      response = Nokogiri::XML(res)
      return response
    rescue => e
      puts e.message
      puts e.backtrace
    end
  end


  def connect

  end

  def is_response_ok?(response)
   status = response.css('ApiResponse').attr('Status')
   if status.to_s == 'OK'
     return true
   else
     return false
   end
  end

  # expects an array
  def is_available?(domain_array)
    puts "Checking domain(s) availability..."
    domain_list = domain_array.join(',')
    avail = Hash.new # {'domain1.com' => true}
    command_input = {:DomainList => domain_list}
    res = send_req('namecheap.domains.check','GET',command_input)

    if is_response_ok?(res)
      res.css('DomainCheckResult').each do |domain|
        available = domain.attr('Available')
        fqdn = domain.attr('Domain')
        puts "Domain [#{fqdn}] is available? [#{available}]"
        avail["#{fqdn}"] = available
      end
    else
      puts "ERROR: #{res.css('Error').text}"
    end
    return avail
  end

  # yeah, namecheap RESTful API is fucking crazy.
  def register(domain)
      puts "Trying to register domain [#{domain}]..."
      command_input = {
          :DomainName => domain,
          :Years => 1,

          #registrant
          :RegistrantFirstName => 'test',
          :RegistrantLastName => 'test',
          :RegistrantAddress1 => 'test',
          :RegistrantCity => 'test',
          :RegistrantStateProvince => 'test',
          :RegistrantPostalCode => '74-589',
          :RegistrantCountry => 'PL',
          :RegistrantPhone => '+1.6613102107',
          :RegistrantEmailAddress => 'lulz@lulz.com',

          #tech
          :TechFirstName => 'test',
          :TechLastName => 'test',
          :TechAddress1 => 'test',
          :TechCity => 'test',
          :TechStateProvince => 'test',
          :TechPostalCode => '74-589',
          :TechCountry => 'PL',
          :TechPhone => '+1.6613102107',
          :TechEmailAddress => 'lulz@lulz.com',

          #admin
          :AdminFirstName => 'test',
          :AdminLastName => 'test',
          :AdminAddress1 => 'test',
          :AdminCity => 'test',
          :AdminStateProvince => 'test',
          :AdminPhone => '+1.6613102107',
          :AdminCountry => 'PL',
          :AdminEmailAddress => 'lulz@lulz.com',
          :AdminPostalCode => '74-589',

          #aux
          :AuxBillingFirstName => 'test',
          :AuxBillingLastName => 'test',
          :AuxBillingAddress1 => 'test',
          :AuxBillingCity => 'test',
          :AuxBillingStateProvince => 'test',
          :AuxBillingPostalCode => '74-589',
          :AuxBillingCountry => 'PL',
          :AuxBillingPhone => '+1.6613102107',
          :AuxBillingEmailAddress => 'lulz@lulz.com' #,put.i
          #:Extended => 'test', # Required for .us, .eu, .ca, .co.uk, .org.uk, .me.uk, .nu , .asia, .com.au, .net.au, .org.au, .es, .nom.es, .com.es, .org.es, .de, .fr TLDs only
      }
      res = send_req('namecheap.domains.create','GET',command_input)
      if is_response_ok?(res)
        domain = res.css('DomainCreateResult')
        puts "Domain [#{domain.attr('Domain')}] - registered [#{domain.attr('Registered')}] - total cost [#{domain.attr('ChargedAmount')}$]"
      else
        puts "ERROR: #{res.css('Error').text}"
      end
  end

  # TODO see here: https://www.namecheap.com/support/api/methods/domains-dns/set-hosts.aspx
  # Possible values A, AAAA, CNAME, MX, MXE, TXT, URL,URL301, FRAME
  def update_record(domain, ip, pfadmin, subdomains_list)
    # TODO handle cases of TLDs like co.uk, where co.uk is the TLD :-)
    sld = domain.split('.').first
    tld = domain.split('.').last

    sendgrid_spf = 'v=spf1 a mx include:sendgrid.net ~all'
    sendgrid_dkim = 'k=rsa; t=s; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDPtW5iwpXVPiH5FzJ7Nrl8USzuY9zqqzjE0D1r04xDN6qwziDnmgcFNNfMewVKN2D1O+2J9N14hRprzByFwfQW76yojh54Xu3uSbQ3JP0A7k8o8GutRF8zbFUA8n0ZH2y0cIEjMliXY4W4LwPA7m4q0ObmvSjhd63O9d8z1XkUBwIDAQAB'

    command_input = {
      :SLD => sld,
      :TLD => tld,

      :Hostname1 => '@',
      :RecordType1 => 'A',
      :Address1 => ip,

      :Hostname2 => pfadmin,
      :RecordType2 => 'CNAME',
      :Address2 => domain,

      :Hostname3 => 'smtp',
      :RecordType3 => 'CNAME',
      :Address3 => 'sendgrid.net',

      :Hostname4 => '@',
      :RecordType4 => 'TXT',
      :Address4 => sendgrid_spf,

      :Hostname5 => 'smtpapi._domainkey',
      :RecordType5 => 'TXT',
      :Address5 => sendgrid_dkim,

      :Hostname6 => 'smtpapi._domainkey.smtp',
      :RecordType6 => 'TXT',
      :Address6 => sendgrid_dkim,
    }

    #NOTE The NameCheap AIP sucks, not my fault :-)
    fieldn = 6
    subdomains = Hash.new

    subdomains_list.each do |subdomain|
       subdomains["Hostname#{fieldn+1}"] = subdomain
       subdomains["RecordType#{fieldn+1}"] = 'CNAME'
       subdomains["Address#{fieldn+1}"] = domain
       fieldn += 1
    end

    command_input = command_input.merge(subdomains)
    res = send_req('namecheap.domains.dns.setHosts','GET',command_input)
    if is_response_ok?(res)
      puts "Domain [#{domain}] - DNS zone file updated successfully."
    else
      puts "ERROR: #{res.css('Error').text}"
    end
  end

  def list_domains
    puts "\nListing registered domains on NameCheap for ApiUser [#{@APIUSER}]..."
    res = send_req('namecheap.domains.getList','GET')
    if is_response_ok?(res)
      res.css('Domain').each do |domain|
        puts "Domain [#{domain.attr('Name')}] - IsExpired? [#{domain.attr('IsExpired')}] - Expires [#{domain.attr('Expires')}]"
      end
    else
      puts "ERROR: #{res.css('Error').text}"
    end
  end
end


# test
ncwrapper = NameCheapWrapper.new
available_domains = ncwrapper.is_available? ['aaaabbbaa1.com', 'aaaabbbaa2.com', 'aaaabbbaa3.com']
available_domains.each do |domain, available|
  ncwrapper.register(domain) if available

  # configure the DNS zone file, using SendGrid as SMTP server
  ncwrapper.update_record(domain, '1.1.1.1', 'pfadmin12345', ['www', 'lol'])

end
#ncwrapper.list_domains



























