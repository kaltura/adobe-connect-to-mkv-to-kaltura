#!/usr/bin/ruby
require "adobe_connect"
def output_data(connect,sco_id)
        response = connect.sco_info(sco_id: sco_id)
        folder_id = response.at_xpath('//sco//@folder-id')
        fresponse = connect.sco_info(sco_id: folder_id)
        folder_name = fresponse.at_xpath('//sco//name').text
	url_path = response.at_xpath('//sco//url-path').text.tr('/', '')
	owner_info = connect.sco_by_url(url_path: url_path)
	owner_name = owner_info.at_xpath('//owner-principal//name').text
	owner_email = owner_info.at_xpath('//owner-principal//email').text
	owner_id = owner_info.at_xpath('//owner-principal//login').text
        print sco_id +',"'+folder_name.tr(',', '').tr('(','').tr(')','') + '","' + response.at_xpath('//sco//name').text.tr(',', '').tr('(','').tr(')','') + '",' + url_path + ',"' + owner_email + '",' + owner_name + '",' + owner_id + "\n"
        #print response.at_xpath('//sco//url-path').text.tr('/', '') + "\n"
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

text=File.open(ARGV[0]).read
text.gsub!(/\r\n?/, "")
text.each_line do |line|
  output_data(connect,line.delete!("\n"))
end

