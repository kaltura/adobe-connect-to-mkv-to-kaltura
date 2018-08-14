#!/usr/bin/ruby
require 'adobe_connect'
require 'date'
require 'csv'

def output_data(connect,sco_id)
  response = connect.sco_info(sco_id: sco_id)
  folder_id = response.at_xpath('//sco//@folder-id')
  folder_response = connect.sco_info(sco_id: folder_id)
  folder_name = folder_response.at_xpath('//sco//name').text
  line = Array.new()
  line.push(sco_id)
  line.push(folder_name.tr(',', '').tr('(','').tr(')',''))
  line.push(response.at_xpath('//sco//name').text.tr(',', '').tr('(','').tr(')',''))
  # if the recording has a description available through the API- add it to the CSV
  if response.at_xpath('//sco//description')
    line.push(response.at_xpath('//sco//description').text.tr(',', '').tr('(','').tr(')',''))
  else
    # we want to maintain the same amount of values in each line array
    line.push('')
  end
  
  line.push(response.at_xpath('//sco//url-path').text.tr('/', ''))
  line.push(DateTime.parse(response.at_xpath('//sco/date-created').text).to_time.to_i.to_s)
  
  found_user = false
  if $user_mapping
    for row in $user_mapping do
      if row[0] == sco_id
        line.push(row[1], '', '')
        found_user = true
        break
      end 
    end
  else
    url_path = response.at_xpath('//sco//url-path').text.tr('/', '')
    owner_info = connect.sco_by_url(url_path: url_path)
    if owner_info.at_xpath('//owner-principal')
        found_user = true
        line.push(owner_info.at_xpath('//owner-principal//email') ? owner_info.at_xpath('//owner-principal//email').text : '')
        line.push(owner_info.at_xpath('//owner-principal//login') ? owner_info.at_xpath('//owner-principal//login').text : '')
        line.push(owner_info.at_xpath('//owner-principal//name') ? owner_info.at_xpath('//owner-principal//name').text : '')
    end
  end
  if !found_user
    line.push('','','')
  end

  # Calculate the duration if available
  if response.at_xpath('//sco/duration')
    line.push(response.at_xpath('//sco/duration').text)
  elsif response.at_xpath('//sco/date-begin') && response.at_xpath('//sco/date-end')
    startTime = DateTime.parse(response.at_xpath('//sco/date-begin').text).to_time.to_i
    endTime = DateTime.parse(response.at_xpath('//sco/date-end').text).to_time.to_i
    duration = endTime - startTime
    line.push(duration.to_s)
  else
    line.push('')
  end
  
  # format line into CSV string and print it out.
  csv_line_string = line.to_csv()
  print csv_line_string
end

if ARGV.length < 1
  puts 'Usage: ' + __FILE__ + ' </path/to/sco/list>'
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
  # slurp file into array of arrays
  $user_mapping = CSV.read(ENV['SCOID_USER_MAPPING'])
end

text = File.open(ARGV[0]).read
text.gsub!(/\r\n?/, '')
text.each_line do |line|
  output_data(connect, line.delete!("\n"))
end
