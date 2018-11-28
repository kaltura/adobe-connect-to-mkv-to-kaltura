#!/usr/bin/ruby
require 'nokogiri'
def get_audio_start_time (file_path)
    dir = File.dirname(file_path) + File::SEPARATOR + 'tmp'
    base_filename = File.basename(file_path, ".*")
    master_xml = '';
    xpath = '';
    if (base_filename.start_with?("cameraVoip"))
        master_xml_pattern = File.join(dir, 'mainstream.xml')
        xpath = ".//Message[Method/text()='playEvent' and String/text()='streamAdded' and Array/Object/streamName[contains(text(), '#{base_filename}')]]/Array/Object/startTime"
    elsif (base_filename.start_with?("ftvoice"))
        master_xml_pattern = File.join(dir, 'ftvoice*.xml')
        xpath = ".//Message[Method/text()='playEvent' and String[contains(text(), '#{base_filename}')]]/@time"
    elsif (base_filename.start_with?("ftstage"))
        master_xml_pattern = File.join(dir,'ftstage*.xml')
        xpath = ".//Message[Method/text()='playEvent' and String[contains(text(), '#{base_filename}')]]/@time"
    end

    files = Dir.glob(master_xml_pattern)
    if !master_xml_pattern || files.empty?
        puts 'No relevant files were found! Skipping';
        return
    end

    for file in files do
        xml = Nokogiri::XML(open(file))
        if (xml.at_xpath(xpath))
            start_time = xml.at_xpath(xpath).text.to_i
        end
    end

    return start_time
end

if ARGV.length < 1
  puts 'Usage: ' + __FILE__ + ' </path/to/file/list>'
  exit 1
end

manifest = File.open(ARGV[0]).read

filter = ''
pieces = Array.new
manifest.each_line.with_index do |line, index|
  start_time = get_audio_start_time(line.delete!("\n"))
  if (start_time && start_time > 0)
    filter += "[#{index}] adelay=#{start_time}|#{start_time}[a#{index}]; "
    pieces.push("[a#{index}]")
  else
    pieces.push("[#{index}]")
  end
end

filter += pieces.join('') + ' amix=' + manifest.lines.count.to_s