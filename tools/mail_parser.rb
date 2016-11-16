# author: @antisnatchor
require 'rubygems'
require 'mail'
require 'optparse'

#TODO parse HTML file with nokogiri, find external images, download them locally and update the HTML content with PF placeholder
options = {}
optparse = OptionParser.new do|opts|
  banner = "Email (.eml) parser for PhishLulz by Michele @antisnatchor Orru'\n" +
           "Usage: ruby mail_parser.rb -e <eml_file_path> -n <output_file_name> -o <output_directory>\n" +
           "NOTE: The script will create 2 files: one with text/plain content, another with text/html content)\n" +
           "NOTE: Once you're done modifying the html file, change its extension to '.erb' before using it in a PhishingFrenzy template'\nOptions:\n"
  opts.banner = banner
  opts.on('-h', '--help', 'Display this screen') do
    puts opts
    exit
  end

  opts.on('-e', '--eml EML', 'Email file to parse in .eml format') do |eml|
    options[:eml] = eml
  end

  opts.on('-n', '--name NAME', 'Output file name') do |name|
    options[:name] = name
  end

  opts.on('-o', '--output OUTPUT', 'Output directory') do |output|
    options[:output] = output
  end
end

optparse.parse!
mandatory_fields = [:eml, :name, :output]
missing_fields = mandatory_fields.select{ |param| options[param].nil? }

if not missing_fields.empty?
  puts "[+] ERROR. Missing options: #{missing_fields.join(', ')}"
  puts optparse
  exit
end

begin
  mail = Mail.read(options[:eml])

  text_plain = mail.text_part.decoded
  text_html = mail.html_part.decoded

  if Dir.exists?(options[:output])
    # create file with text/plain content
    f = File.new("#{options[:output]}/#{options[:name]}_plain.txt", "w")
    f.write(text_plain)
    f.close

    # create file with text/html content
    f = File.new("#{options[:output]}/#{options[:name]}_html.erb", "w")
    f.write(text_html)
    f.close
    puts "[+] All done! Files #{options[:name]}_plain.txt and #{options[:name]}_html.erb created in directory #{options[:output]}"
  else
    puts "[-] ERROR: specified directory #{options[:output]} doesn't exist"
  end

rescue Exception => e
  puts "[-] ERROR: #{e.message}"
  puts e.backtrace
end
