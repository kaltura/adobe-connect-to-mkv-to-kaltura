#!/usr/bin/ruby
require "adobe_connect"
require "date"
require "csv"

def output_data(connect,sco_id)
        response = connect.sco_info(sco_id: sco_id)
        folder_id = response.at_xpath('//sco//@folder-id')
        fresponse = connect.sco_info(sco_id: folder_id)
        folder_name = fresponse.at_xpath('//sco//name').text
<<<<<<< HEAD
        print sco_id +',"'+folder_name.tr(',', '').tr('(','').tr(')','') + '","' + response.at_xpath('//sco//name').text.tr(',', '').tr('(','').tr(')','') + '",' 
        print response.at_xpath('//sco//description') ? '"' + response.at_xpath('//sco//description').text.tr(',', '').tr('(','').tr(')','') + '",' : ','
        print response.at_xpath('//sco//url-path').text.tr('/', '') + ','
        print DateTime.parse(response.at_xpath('//sco/date-created').text).to_time.to_i.to_s + ','
        if $user_mapping
          for row in $user_mapping do
            if row[0] == sco_id
              print row[1]
            end 
          end
        else 
          url_path = response.at_xpath('//sco//url-path').text.tr('/', '')
          owner_info = connect.sco_by_url(url_path: url_path)
          owner_id = owner_info.at_xpath('//owner-principal//login').text
          print owner_id
        end 
        print "\n"
end

if ARGV.length < 1
  puts "Usage: " + __FILE__ + " </path/to/sco/list>"
  exit 1
end

# start by configuring it with a username, password, and domain.
AdobeConnect::Config.declare do
  username ENV['AC_USERNAME']
  password ENV['AC_PASSWD']
  domain   ENV['AC_ENDPOINT']
end

connect = AdobeConnect::Service.new

# log in so you have a session
connect.log_in #=> true

$user_mapping = nil
if ENV['SCOID_USER_MAPPING'] && File.file?(ENV['SCOID_USER_MAPPING'])
  #slurp file into array of arrays
  $user_mapping = CSV.read(ENV['SCOID_USER_MAPPING'])
end
  
text=File.open(ARGV[0]).read
text.gsub!(/\r\n?/, "")
text.each_line do |line|
  output_data(connect,line.delete!("\n"))
end

