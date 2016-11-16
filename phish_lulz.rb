# author: @antisnatchor
require 'rubygems'
require 'fog'
require 'yaml'
require 'optparse'

VERSION = '1.0'
CURRENT_DIR = File.expand_path(File.dirname(__FILE__))

loaded_config = "#{CURRENT_DIR}/config.yaml"
config = YAML.load_file(loaded_config)

options = {}
optparse = OptionParser.new do|opts|
  banner = "PhishLulz by @antisnatchor, version #{VERSION}\n"
  actions =
          "\n          create - create a new instance" +
          "\n          start - start an already created instance given its id" +
          "\n          stop - stop an instance given its id" +
          "\n          terminate - terminate an instance given its id" +
          "\n          list - list existing instances" +
          "\n          gencert - generates a certificate, CSR and key using the PhishLulz CA"
  opts.banner = banner
  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end

  opts.on('-a', '--action ACTION', 'Actions: create, start, stop, terminate, list instances.' + actions) do |action|
    options[:action] = action
  end

  opts.on('-c', '--config CONFIG', 'Configuration file to load (defaults to config.yaml in the current directory)') do |c|
    options[:config] = c
    loaded_config = c
    config = YAML.load_file(c)
  end
end

optparse.parse!
mandatory_fields = [:action]
missing_fields = mandatory_fields.select{ |param| options[param].nil? }
puts "[+] Loaded configuration file: #{loaded_config}"

def update_ca_config
  begin
    if File.foreach("#{CURRENT_DIR}/certification-authority/openssl.cnf").grep(/__PHISHLULZ_CHANGE_ME__/).empty?
      # nothing to do, good to go, return
      return
    else
      # change dir variables updating absolute path
      ca_config = "#{CURRENT_DIR}/certification-authority/openssl.cnf"
      ca_int_config = "#{CURRENT_DIR}/certification-authority/intermediate/openssl.cnf"

      conf = File.read(ca_config)
      updated = conf.gsub(/__PHISHLULZ_CHANGE_ME__/, "#{CURRENT_DIR}/certification-authority")
      File.open(ca_config, "w") { |file| file << updated }

      conf_int = File.read(ca_int_config)
      updated = conf_int.gsub(/__PHISHLULZ_CHANGE_ME__/, "#{CURRENT_DIR}/certification-authority/intermediate")
      File.open(ca_int_config, "w") { |file| file << updated }
      puts "[+] Updated root and intermediate CA config files."
    end
  rescue Exception => e
    puts "[-] ERROR updating CA config files.\n #{e.message}"
  end
end

# updates root and intermediate CA config files
update_ca_config

if not missing_fields.empty?
  puts optparse
  puts "[-] ERROR. Missing option: #{missing_fields.join(', ')}"
  exit
end


# NOTE: don't change the following 4 variables ;-)
PROVIDER = config['provider'] # Amazon. Other available providers: http://fog.io/about/provider_documentation.html
REGION = config['region'] # USA, Oregon
INSTANCE_TYPE = config['instance']['type'] # m1.small (1.7 GB ram), t1.micro (0.7 GB ram)
INSTANCE_AMI = config['instance']['ami'] # antisnatchor's Social Engineering AMI

AWS_ACCESS_KEY_ID = config['security']['key_id']
AWS_SECRET_ACCESS_KEY = config['security']['access_key']

# The script assumes there is already a public key linked to this account, and locally the corresponding private key.
SECURITY_KEY_PAIR = config['security']['keypair_name']
SECURITY_KEY_PEM_PATH = config['security']['keypair_path']
SSH_USERNAME = config['security']['ssh_user']

CA_PASSPHRASE = config['security']['ca_passphrase']

# NOTE: make sure you crate a security group with the above open ports before you create a new instance.
# Just open port 80/443 other than classic 22.
SECURITY_GROUP = config['security']['security_group']

CA_PATH = './certification-authority/intermediate'
@sshd_retries = 5

def connect
  begin
    connection = Fog::Compute.new({
       :provider => PROVIDER,
       :region => REGION,
       :aws_access_key_id => AWS_ACCESS_KEY_ID,
       :aws_secret_access_key => AWS_SECRET_ACCESS_KEY
       #:connection_options => {:proxy => 'http://127.0.0.1:9090', :ssl_verify_peer => false}
   })
    @instances = connection.servers
  rescue Exception => e
    puts "[-] ERROR: #{e.message}"
  end
end

def list
  connect
  @instances.table([:id, :tags, :state,
                    :flavor_id, :public_ip_address,
                    :image_id, :security_group_ids, :created_at])
end

def is_ssh_started(se_vm)
  puts "[+] Checking if SSHd has started..."
  if @sshd_retries > 0
    begin
      execute se_vm, "echo ssh_started"
      puts "[+] SSHd is running."
    rescue Exception => e
      puts "[-] SSHd has not started yet, waiting 10 seconds and trying again..."
      sleep 10
      @sshd_retries -= 1
      is_ssh_started se_vm
    end
  else
    puts "[-] Giving up. Instance is running but not properly configured."
  end
end

def create
  connect
  puts "[+] Enter a name for your instance (ex. test_se_vm):"
  instance_name = $stdin.gets.chomp
  puts "[+] Enter the FQDN for the PhishingFrenzy admin UI (ex. pfadmin12345.yourphishingdomain.com):"
  pf_fqdn = $stdin.gets.chomp
  puts "[+] Enter the FQDN for the phishing campaign (ex. mail.yourphishingdomain.com)\n[+] NOTE: make sure you use the same setting when creating a new phishing campaign on PhishingFrenzy:"
  phishing_fqdn = $stdin.gets.chomp
  begin
    se_vm = @instances.create(
        :image_id => INSTANCE_AMI,
        :flavor_id => INSTANCE_TYPE,
        :key_name => SECURITY_KEY_PAIR,
        :tags => {:Name => instance_name},
        :security_group_ids => [SECURITY_GROUP]
    )

    se_vm.username = SSH_USERNAME
    se_vm.private_key_path = SECURITY_KEY_PEM_PATH

    puts "[+] Waiting for instance to be ready. This takes approx 2 minutes..."
    se_vm.wait_for { print "."; ready? }
    sleep 30
    puts "\n[+] New Social Engineering instance ready: #{se_vm.id.to_s}.\n[+] Waiting 60 seconds for SSHd to start..."
    sleep 60

    # verify if SSHs is running. If it isn't, wait 10 seconds and recursively call itself.
    is_ssh_started se_vm

    # update the PhishingFrenzy DB global_settings table and Apache Vhost declaration
    execute se_vm, "mysql -u pf_prod -e 'UPDATE global_settings SET site_url=\"https://#{pf_fqdn}\" WHERE id=1;' pf_prod"
    execute se_vm, "sudo sed -i 's/pfadmin.local/#{pf_fqdn}/' /etc/apache2/pf.conf"

    # update the public ip configuration setting in BeEF
    execute se_vm, "sudo sed -i 's/__se_vm_phishing_fqdn__/#{phishing_fqdn}/' /home/sesl/BeEF/beef_configuration.yaml"

    # generate SSL certificate for the admin UI and upload them to the machine
    upload_certificate(pf_fqdn, se_vm.public_ip_address) if generate_certificate(pf_fqdn)

    # restart Apache to reflect changes
    execute se_vm, "sudo service apache2 restart"

    temp_action = "[+] <!!! IMPORTANT !!!>\n SSH in the machine with\n ssh -v -i #{SECURITY_KEY_PEM_PATH} sesl@#{se_vm.public_ip_address}\nand run the following command to start BeEF/Sidekiq:\nbash start_services.sh &\n[+] </!!! IMPORTANT !!!>\n\n"
    all_done = temp_action + "[+] All DONE! Start the Lulz!!!\nYou can now connect to the new instance doing the following:\n" +
        " 1. ssh -v -o \"ServerAliveInterval 180\" -i #{SECURITY_KEY_PEM_PATH} sesl@#{se_vm.public_ip_address}\n" +
        " 2. point the browser where you imported the PhishLulz CA certificate to https://#{pf_fqdn}\n" +
        "\nNOTE: The 'sesl' user has root privileges via sudo (without password)." + 
        "NOTE: if you need HTTPs, generate a CSR with the following, specifying the FQDN as Common Name:\n" + 
        "openssl req -new -newkey rsa:2048 -nodes -keyout KEY-NAME.key -out CSR-NAME.csr"
    puts all_done
  rescue Exception => e
    puts "[-] ERROR: #{e.message}"
  end
end

def upload_certificate(cn, ip)
  success = false
  begin
    puts "[+] Uploading SSL certificate and key:"
    IO.popen(["scp","-oStrictHostKeyChecking=no","-i","#{SECURITY_KEY_PEM_PATH}","#{CA_PATH}/certs/#{cn}.cert.pem","sesl@#{ip}:/home/sesl/ssl_certs/#{cn}.cert.pem"],"r+")
    IO.popen(["scp","-oStrictHostKeyChecking=no","-i","#{SECURITY_KEY_PEM_PATH}","#{CA_PATH}/private/#{cn}.key.pem","sesl@#{ip}:/home/sesl/ssl_certs/#{cn}.key.pem"],"r+")
    sleep 4
  rescue Exception => e
    puts "[-] ERROR. #{e.message}"
  end
  success
end

def generate_certificate(cn=nil)
  success = false
  begin
    if cn == nil
      puts "[+] Enter Common Name (FQDN) to be used:"
      cn = $stdin.gets.chomp
    end

    # generate private key
    puts "[+] Generating SSL certificate for #{cn}"
    puts "[+] Generating private key..."
    IO.popen(["openssl","genrsa","-out","#{CA_PATH}/private/#{cn}.key.pem","2048","-batch"],"r+")

    # generate certificate sign request
    sleep 2
    puts "[+] Generating CSR..."
    IO.popen(["openssl","req","-config","#{CA_PATH}/openssl.cnf","-key","#{CA_PATH}/private/#{cn}.key.pem","-new","-batch",
              "-subj","/CN=#{cn}","-sha256","-out","#{CA_PATH}/csr/#{cn}.csr.pem"],"r+")

    # generate final certificate
    sleep 2
    puts "[+] Generating final certificate..."
    IO.popen(["openssl","ca","-config","#{CA_PATH}/openssl.cnf","-extensions","server_cert","-days","375","-notext",
              "-md","sha256","-in","#{CA_PATH}/csr/#{cn}.csr.pem","-out","#{CA_PATH}/certs/#{cn}.cert.pem","-batch","-passin","pass:#{CA_PASSPHRASE}"],"r+")
    sleep 1
    success = true
  rescue Exception => e
    puts "[-] ERROR. #{e.message}"
  end
  success
end

def start
  connect
  begin
    puts "[+] You want to start an instance. Enter instance ID (ex. i-05967684):"
    id = $stdin.gets.chomp
    instance = @instances.get(id)
    instance.start
    puts "[+] Instance is now starting."
  rescue Exception => e
    puts "[-] ERROR. Instance NOT started. Error message: #{e.message}"
  end
end

def stop
  connect
  begin
    puts "[+] You want to stop an instance. Enter instance ID (ex. i-05967684):"
    id = $stdin.gets.chomp
    instance = @instances.get(id)
    instance.stop
    puts "[+] Instance is now stopping."
  rescue Exception => e
    puts "[-] ERROR. Instance NOT stopped. Error message: #{e.message}"
  end
end

def terminate
  connect
  begin
    puts "[+] You want to terminate an instance. Enter instance ID (ex. i-05967684):"
    id = $stdin.gets.chomp
    instance = @instances.get(id)
    instance.destroy
    puts "[+] Instance is now terminating."
  rescue Exception => e
    puts "[-] ERROR. Instance NOT terminated. Error message: #{e.message}"
  end
end

# execute cmd on the target instance via SSH
def execute(instance, cmd)
  puts "[+] Executing command:\n#{cmd}"
  result = instance.ssh(cmd)
  puts "(cmd stdout):\n#{result.first.stdout}"
end

#================= main ===========
cmd = options[:action]
case cmd
  when "list"
    list
  when "create"
    create
  when "start"
    start
  when "stop"
    stop
  when "terminate"
    terminate
  when "gencert"
    generate_certificate
  when "help"
    puts optparse
  else
    puts optparse
    puts "[-] ERROR. Argument of --action or -a is wrong."
end

