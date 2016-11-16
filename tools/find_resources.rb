# author: Michele @antisnatchor Orru, November 2014
require 'nokogiri'
require 'uri'
require 'net/http'
require 'resolv'
require 'thread'


DOMAINS = Array.new
SUBDOMAINS = Array.new

USE_PROXY = false
PROXY_HOST = "127.0.0.1"
PROXY_PORT = 9090

NAMESERVER = '8.8.8.8'
NAMESERVER_2 = '8.8.8.4'

# how many domains you want to do recon against simultaneously.
# a thread pool of size 5 will run recon against 5 domains at the same time.
THREAD_POOL_SIZE = 5

# file to read the subdomains from, from the tools/wordlists dir
# format as following:
# admin.
# webmail.
# ...
SUBDOMAIN_LIST = 'subdomain_list_multi.list'

@current_cookies = ""
@dns = Resolv::DNS.new( :nameserver => [NAMESERVER, NAMESERVER_2] )

# returns the HTTP response, or error
def request(uri, method, cookies)
 #puts "Current URI: #{uri}"
 uri = URI(uri)
 http = nil
 if USE_PROXY
 	 http = Net::HTTP.new(uri.host, uri.port, PROXY_HOST, PROXY_PORT)
 else
 	 http = Net::HTTP.new(uri.host, uri.port)
 end

 http.read_timeout = 4 # 4 seconds read timeout
 http.open_timeout = 4
 if uri.scheme == "https"
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_NONE
 end

 request = nil
 if method == "OPTIONS"
   request = Net::HTTP::Options.new(uri.request_uri, cookies)
 else # otherwise GET
   request = Net::HTTP::Get.new(uri.request_uri, cookies)
 end
 
 begin
	 response = http.request(request)

	 case response
	  when Net::HTTPSuccess
	    then 
	    return response
	  when Net::HTTPRedirection # if you get a 3xx response
	    then 
	    # handles stupid implementations like Location: /Login
	    location = response['Location']
	    #puts "Location redirect to: #{location}"
	    if response['Set-cookie'] != nil && !@current_cookies.include?(response['Set-cookie'])
	    	@current_cookies += response['Set-cookie']
	    end
	    cookies = {'Cookie'=> @current_cookies}

	    if location.start_with?("/")
	    	location = "#{uri.scheme}://#{uri.host}:#{uri.port}#{location}"
	    	#puts "Final location: #{location}"
	    end
	    return request(location, "GET", cookies)
	  else
	    return [nil, "Response error"]
	 end
 # ctaching different exceptions in case we need to do something on it in the future
 rescue SocketError => se # domain not resolved
 	return [nil, "Domain not resolved"]
 rescue Timeout::Error => timeout # timeout in open/read
 	return [nil, "Timeout in open or read"]
 rescue Errno::ECONNREFUSED => refused # connection refused
 	return [nil, "Connection refused"]
 rescue Exception => e
 	#puts e.message
 	#puts e.backtrace
 	return [nil, e.message]
 end
end

def get_title(doc)
	doc.css('title')[0] || "N/A"
end

def get_allowed_methods(response)
 # the following is as per-Sol requirement (based on his assumption)
  allow = "GET, POST"
  if response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPRedirection)
  	if response['Allow'] != nil
  		allow = response['Allow']
  	end
  end
  return allow
end

def get_server_header(response)
  server = "N/A"
  if response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPRedirection)
  	if response['Server'] != nil
  		server = response['Server']
  	else
  		server += ": Header missing"
  	end
  else
  	server += ": #{response[1]}"
  end
  return server
end

def load_domains(file)
 begin
  File.open(file).each do |line|
   DOMAINS << line.chomp
  end
 rescue Exception => e
 	print "Error!\n #{e.message}"
 end
end

def load_subdomains_list 
 begin
  File.open("#{File.expand_path(File.dirname(__FILE__))}/wordlists/#{SUBDOMAIN_LIST}").each do |line|
   SUBDOMAINS << line.chomp
  end
 rescue Exception => e
 	print "Error!\n #{e.message}"
 end
end

def recon(domain)
	count = 1
	size = SUBDOMAINS.size
	update = 100 

	puts "> Starting recon of (#{domain}) subdomains...."
	recon_output = File.new("#{File.expand_path(File.dirname(__FILE__))}/findresources_#{domain}.csv", "w+")
	SUBDOMAINS.each do |subdomain| 			
		begin		
			fqdn = "#{subdomain}#{domain}"	
			puts "(#{domain}) Status: #{count}/#{size}" if count % update == 0 # every 100 subdomains give an update
  			ip = @dns.getaddress(fqdn.chomp)
  			@current_cookies = ""


			["http", "https"].each do |scheme|
			  # console-only output (csv like, comma separated)
			  # ip, fqdn, port, <title> tag, OPTIONS, server header
			  output = Array.new

				  url = "#{scheme}://#{fqdn}/"
				  response = request(url, "GET", nil)
				  
				  if response != nil && (response.is_a?(Net::HTTPOK) || response.is_a?(Net::HTTPRedirection))
				  	# resolve the fqdn getting the IP
				  	output << ip
				    output << fqdn.chomp
				    if scheme == "http"
			          	output << 80
			        else
			          	output << 443
			        end
				  	doc = Nokogiri::HTML(response.body)
				  	output << '"' + get_title(doc).to_s.strip.gsub(/\s+/, " ") + '"'

				  	response_opts = request(url, "OPTIONS", nil)
					output << '"' + get_allowed_methods(response_opts) + '"'
				  	output << '"' + get_server_header(response) + '"'

				    csv_output = output.join(", ")
				  	puts csv_output
				  	recon_output.write("#{csv_output}\n")
				  end
			end
	    rescue Resolv::ResolvError => re
		  	#puts "Skipping domain #{fqdn.chomp} as it doesn't resolve."
		end
		count += 1
    end

    recon_output.close
    puts "> Finished recon of (#{domain})!"
end

puts "Very simple HTTP response parser coded by @antisnatchor.\nThe 'nokogiri' and 'dnsruby' gems are required."
if ARGV[0] == nil 
	puts "Usage: ruby find_resources.rb /file/with/domains\n\n" +
			 "For each domain contained in the file, enumerate over 1900 subdomains:\n" +
			 "domain1.com\n" +
			 "domain2.com\n\n" +
			 "Check the subdomain_list_multi.list file to see which subdomains are being enumerated."
else

	load_domains(ARGV[0])
    load_subdomains_list

	puts "> Loaded #{DOMAINS.size} domains to do subdomain recon against\n" +
	     "> Loaded #{SUBDOMAINS.size} subdomains from subdomain_list_multi.list\n" + 
	     "> Thread Pool Size (concurrent domains): 5\n" + 
		 "> Using the following nameservers to resolve domains: #{NAMESERVER}, #{NAMESERVER_2}\n"

	domains_queue = Queue.new
	DOMAINS.each{|x| domains_queue.push x }

    iterations = DOMAINS.size / THREAD_POOL_SIZE
    count = 1
    puts "> #{iterations} iterations needed having thread pool size of #{THREAD_POOL_SIZE}"

    while count <= iterations do
    	workers = (0...THREAD_POOL_SIZE).map do
        Thread.new do
          begin
            domain = domains_queue.pop(true)
            unless domain.nil?
              recon domain
            end
          rescue ThreadError
          end
        end
		  end
		workers.map(&:join)
	  count += 1
    end
end



