#!/usr/bin/ruby
require 'nokogiri'

if ARGV.length < 1
  puts 'Usage: ' + __FILE__ + ' </path/to/edit/xml>'
  exit 1
end

def get_edit_points_array (edit_xml_path)
    xml = Nokogiri::XML(open(edit_xml_path))
    edit_points = xml.xpath('.//editPoint');

    edit_points_array = Array.new
    edit_points.each do |edit_point|
        edit_begin = edit_point.at_xpath('./@editBegin').text.to_i
        edit_end = edit_point.at_xpath('./@editEnd').text.to_i
        edit_points_array.push({'editBegin' => edit_begin, 'editEnd' => edit_end});
    end

    return edit_points_array
end


edit_file = ARGV[0]
if (!File.exist?(edit_file))
    exit 1;
end

edit_points_array = get_edit_points_array(edit_file)

filter_complex = ''
start_point = 0
parts = Array.new
edit_points_array.each.with_index do |elem, index|
    diff = elem['editBegin'] - start_point
    if (diff == 0)
        #no need to handle this element - it starts where the previous element ended
        start_point = elem['editEnd']
        next
    end

    filter_complex += "[0:a]atrim=start=#{start_point}:end=" + elem['editBegin'].to_s + "[a#{index}];"
    start_point = elem['editEnd']
    parts.push("[a#{index}]")
end

final = edit_points_array.length
parts.push("[a#{final}]")
filter_complex += "[0:a]atrim=start=#{start_point}[a#{final}];" + parts.join('') + 'concat=n=' + parts.length.to_s + ':v=0:a=1[outa]'
puts filter_complex