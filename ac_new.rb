#!/usr/bin/ruby
require "json"
require "selenium-webdriver"
gem "test-unit"
require "test/unit"
require 'open3'
require 'shellwords'
require 'kaltura'
require 'logger'


include Kaltura

class Vconn1 < Test::Unit::TestCase


  def setup
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    @logger.formatter = proc do |severity, datetime, progname, msg| 
	fileLine = "";
	caller.each do |clr|
		unless(/\/logger.rb:/ =~ clr) 
			fileLine = clr; 
			break;
		end  
	end  
	fileLine = fileLine.split(':in `',2)[0];
	fileLine.sub!(/:(\d)/, '(\1');
	"#{datetime}: #{severity} #{fileLine}): #{msg}\n"
    end

    @profile = Selenium::WebDriver::Firefox::Profile.new
    @profile["plugin.state.flash"] = 2
    @profile["plugins.flashBlock.enabled"] = 0
    @profile["default_content_settings.state.flash"] = 1
    @profile["RunAllFlashInAllowMode"]=1
    @profile["AllowOutdatedPlugins"]=1
    options = Selenium::WebDriver::Firefox::Options.new
    @caps = Selenium::WebDriver::Remote::Capabilities.firefox(:firefox_profile => @profile)

    @base_url = ENV['AC_ENDPOINT']
    @driver = Selenium::WebDriver.for :firefox, desired_capabilities:@caps
    @driver.manage.window.maximize
    #@driver.manage.window.full_screen


    @accept_next_alert = true
    @driver.manage.timeouts.implicit_wait = 30
    @verification_errors = []
  end
  
  def teardown
    @driver.quit
    assert_equal [], @verification_errors
  end
  
  def test_vconn1

    out_dir=ENV['OUTDIR'] + '/'
    meeting_id=ENV['MEETING_ID']
    entry_name=ENV['MEETING_NAME']
    cat_name=ENV['CATEGORY_NAME']

    if ENV['FFMPEG_BIN']
	    ffmpeg_bin=ENV['FFMPEG_BIN']
    else
	    ffmpeg_bin='ffmpeg'
    end

    if ENV['FFPROBE_BIN']
	    ffprobe_bin=ENV['FFPROBE_BIN']
    else
	    ffprobe_bin='ffprobe'
    end
    recording_file=out_dir + meeting_id + '.mkv'
    audio_file=out_dir + meeting_id + ".mp3"
    full_recording_file=out_dir + meeting_id + ".full.mkv"

    # get duration from the MP3 file, we'll use that to determine how long ffmpeg should be recording for 
    duration, stdeerr, status = Open3.capture3(ffprobe_bin + " -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "+audio_file.shellescape)
    if ! status.success?
      log.error('Failed to get audio track duration. Exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    dur_sec=duration.split(':').map { |a| a.to_i }.inject(0) { |a, b| a * 60 + b}
    # since AC takes forever to load the recording, add 2 minutes to the actual recording's duration, we'll cut the extra off later
    extra_duration=dur_sec.to_f + 120

    @driver.get(@base_url + "/system/login?logintype=oldstyle&next=/admin")
    @driver.find_element(:id, "name").send_keys ENV['AC_USERNAME']
    @driver.find_element(:id, "pwd").send_keys ENV['AC_PASSWD']
    @driver.find_element(:id, "login-button").click
    @driver.get(@base_url + "/" + meeting_id +"?launcher=false&fcsContent=true&pbMode=normal")

    # FFmpeg magic

    # record X11's display 
    ffmpeg_x11grab_command=ffmpeg_bin + ' -s 1280x720 -framerate 30 -f x11grab -i :' + ENV['X_SERVER_DISPLAY_NUM'] + ' -t ' + extra_duration.to_s + ' -vf "crop=in_w:in_h-147" -y ' + recording_file.shellescape
    @logger.info('X11grab COMMAND IS: ' + ffmpeg_x11grab_command)
    
    system ffmpeg_x11grab_command
    if $?.exitstatus != 0
      @logger.error('ffmpeg x11grab command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    
    # use scene detector feature to determine when the recording had actually started
    first_scene, stdeerr, status = Open3.capture3(ffmpeg_bin + " -i " + recording_file +" -filter:v \"select='gt(scene,0.4)',showinfo\"  -frames:v 1  -f null  - 2>&1|grep pts_time|sed 's/.*pts_time:\\([0-9.]*\\).*/\\1/'")
    if $?.exitstatus != 0
      @logger.error('ffmpeg scene detection command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    first_scene=first_scene.delete!("\n")

    # trim original screen recording so that it starts from when AC actually started playing the recording
    ffmpeg_trim_command=ffmpeg_bin + " -i " + recording_file + " -ss " + first_scene + " -t " + dur_sec.to_s + " -c copy -strict -2 -an -y " + out_dir +meeting_id+".final.mkv"	

    @logger.info("Trim COMMAND IS: " + ffmpeg_trim_command)
    system ffmpeg_trim_command 
    if $?.exitstatus != 0
      @logger.error('ffmpeg trim command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end

    # merge video and audio files
    ffmpeg_merge_command=ffmpeg_bin + " -i " + out_dir +meeting_id+ ".final.mkv -i " + audio_file + " -c copy -y " + full_recording_file.shellescape

    @logger.info("Merge COMMAND IS: " + ffmpeg_merge_command)
    system ffmpeg_merge_command 
    if $?.exitstatus != 0
      @logger.error('ffmpeg audio and video merge command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end

    if File.exist?(full_recording_file) 
      @logger.info("Final output saved to: " + full_recording_file + " :)")
    else
      @logger.error("Something failed and I couldn't find a " + full_recording_file + " to process:(")
      return false
    end

    # ingest to Kaltura
    if ENV['KALTURA_BASE_ENDPOINT'] and ENV['KALTURA_PARTNER_ID'] and ENV['KALTURA_PARTNER_SECRET']
      ingest_to_kaltura(ENV['KALTURA_BASE_ENDPOINT'],ENV['KALTURA_PARTNER_ID'], ENV['KALTURA_PARTNER_SECRET'], ENV['KALTURA_CAT_ID'], cat_name,entry_name,full_recording_file)
    else
      @logger.warn("Skipping Kaltura ingestion, missing KALTURA_BASE_ENDPOINT, KALTURA_PARTNER_ID or KALTURA_PARTNER_SECRET ENV vars")
    end
  end


  def ingest_to_kaltura(base_endpoint,partner_id, secret, parent_cat_id, cat_name, entry_name,vid_file_path)
    config = KalturaConfiguration.new()
    config.service_url = base_endpoint
    client = KalturaClient.new(config);
    client.ks = client.session_service.start(
	  secret,
	  nil,
	  Kaltura::KalturaSessionType::ADMIN,
	  partner_id,
	  nil,
	  "disableentitlement"
    )

    # check whether category already exists
    filter = KalturaCategoryFilter.new()
    full_cat_path=ENV['KALTURA_ROOT_CATEGORY_PATH']
    filter.full_name_equal = full_cat_path + ">" +cat_name
    pager = KalturaFilterPager.new()
    results = client.category_service.list(filter, pager)
    # if not, create it
    if !results.total_count
		category = KalturaCategory.new()
		category.parent_id=parent_cat_id
		category.name = cat_name
		results = client.category_service.add(category)
		@logger.info("Created category: " + cat_name + ", cat ID: "+results.id)
    end
    upload_token = KalturaUploadToken.new()

    results = client.upload_token_service.add(upload_token)
    upload_token_id=results.id

    file_data = File.open(vid_file_path)
    resume = false
    final_chunk = true
    resume_at = -1

    results = client.upload_token_service.upload(upload_token_id, file_data, resume, final_chunk, resume_at)
    entry = KalturaMediaEntry.new()
    entry.media_type = KalturaMediaType::VIDEO
    entry.name = entry_name
    entry.description = "AC original ID: " + ENV['MEETING_ID']
    entry.tags = ENV['MEETING_ID']
    entry.categories=full_cat_path + ">" +cat_name

    results = client.media_service.add(entry)
    entry_id = results.id
    resource = KalturaUploadedFileTokenResource.new()
    resource.token = upload_token_id

    results = client.media_service.add_content(entry_id, resource)
    if !defined? results.id
      @logger.error("media_service.add_content() failed:(")
    end
    @logger.info("Uploaded " + vid_file_path + ", entry ID: " + results.id)
  end  

  def element_present?(how, what)
    @driver.find_element(how, what)
    true
  rescue Selenium::WebDriver::Error::NoSuchElementError
    false
  end
  
  def alert_present?()
    @driver.switch_to.alert
    true
  rescue Selenium::WebDriver::Error::NoAlertPresentError
    false
  end
  
  def verify(&blk)
    yield
  rescue Test::Unit::AssertionFailedError => ex
    @verification_errors << ex
  end
  
  def close_alert_and_get_its_text(how, what)
    alert = @driver.switch_to().alert()
    alert_text = alert.text
    if (@accept_next_alert) then
      alert.accept()
    else
      alert.dismiss()
    end
    alert_text
  ensure
    @accept_next_alert = true
  end
end
