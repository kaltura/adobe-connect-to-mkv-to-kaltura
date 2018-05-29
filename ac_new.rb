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

    # read mandatory ENV params
    # I love Ruby but I find instance_variable_set() and instance_variable_get() messy and not worth it...
    # this is actually one of these mighty rare occasions where PHP outshines ruby in terms of cleanliness of syntax with the `$$` or variable variable. 
    # so, verify existence first and set later.. less "cool" but you can't have it all:)
    
    mandatory_env_vars = ['OUTDIR', 'MEETING_ID', 'MEETING_NAME', 'CATEGORY_NAME', 'AC_USERNAME', 'AC_PASSWD', 'X_SERVER_DISPLAY_NUM'] 
    
    mandatory_env_vars.each do |mandatory_var|
      if ! ENV[mandatory_var] or ENV[mandatory_var].empty?
	@logger.error('Missing ENV var ' + mandatory_var + ':( Make sure you export it.')
	return false
      end
    end

    out_dir=ENV['OUTDIR'] + '/'
    # let's strip spaces just to be on the safe side
    meeting_id=ENV['MEETING_ID'].strip
    entry_name=ENV['MEETING_NAME']
    cat_name=ENV['CATEGORY_NAME']
    ac_user=ENV['AC_USERNAME']
    ac_passwd=ENV['AC_PASSWD']
    x_display=ENV['X_SERVER_DISPLAY_NUM']

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
    
    resolution='1280x720'
    frame_rate='30'
    audio_file=out_dir + meeting_id + '.mp3'
    recording_file=out_dir + meeting_id + '.mkv'
    full_recording_file=out_dir + meeting_id + '.full.mkv'
	
    basedir=File.dirname(__FILE__) 
    @logger.info(basedir + '/get_ac_audio.sh ' + meeting_id)
    system basedir + '/get_ac_audio.sh ' + meeting_id 
    if $?.exitstatus != 0 or ! File.exist?(audio_file)
	    @logger.error("Failed to obtain audio file :(")
	    return false
    end

    # get duration from the MP3 file, we'll use that to determine how long ffmpeg should be recording for 
    dur_sec, stdeerr, status = Open3.capture3(ffprobe_bin + " -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 " + audio_file.shellescape)
    dur_sec=dur_sec.delete!("\n")
    if ! status.success?
      log.error('Failed to get audio track duration. Exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    # since AC takes forever to load the recording, add 2 minutes to the actual recording's duration, we'll cut the extra off later
    extra_duration=dur_sec.to_f + 120

    if ENV['AC_LOGIN_REQUIRED'] === "true"
      @driver.get(@base_url + "/system/login?logintype=oldstyle&next=/admin")
      @driver.find_element(:id, "name").send_keys ac_username
      @driver.find_element(:id, "pwd").send_keys ac_passwd
      @driver.find_element(:id, "login-button").click
    end
    @driver.get(@base_url + "/" + meeting_id +"?launcher=false&fcsContent=true&pbMode=normal")

    # FFmpeg magic
    # record X11's display 
    if ! ffmpeg_x11_grab(ffmpeg_bin,resolution, frame_rate, x_display, extra_duration.to_s, recording_file)
      return false
    end
    
    # use scene detector feature to determine when the recording had actually started
    if ! first_scene=ffmpeg_detect_scene_start_time(ffmpeg_bin, recording_file, 1)
      return false
    end

    # trim original screen recording so that it starts from when AC actually started playing the recording
    if ! ffmpeg_trim_video(ffmpeg_bin, recording_file, first_scene, dur_sec.to_s, out_dir + meeting_id + ".final.mkv")
      return false
    end

    # merge video and audio files
    if ! ffmpeg_merge_vid_and_aud_tracks(ffmpeg_bin, out_dir + meeting_id + ".final.mkv", audio_file, full_recording_file)
      return false
    end

    if File.exist?(full_recording_file) 
      @logger.info("Final output saved to: " + full_recording_file + " :)")
    else
      @logger.error("Something failed and I couldn't find a " + full_recording_file + " to process:(")
      return false
    end

    # verify the Kaltura params are set before attempting to ingest to Kaltura
    kaltura_mandatory_vars = ['KALTURA_BASE_ENDPOINT', 'KALTURA_PARTNER_ID', 'KALTURA_PARTNER_SECRET', 'KALTURA_CAT_ID', 'KALTURA_ROOT_CATEGORY_PATH'] 
    
    kaltura_mandatory_vars.each do |mandatory_var|
      if ! ENV[mandatory_var] or ENV[mandatory_var].empty?
	@logger.warn('Skipping Kaltura ingestion, missing ENV var ' + mandatory_var)
	return
      end
    end
    
    ingest_to_kaltura(ENV['KALTURA_BASE_ENDPOINT'],ENV['KALTURA_PARTNER_ID'], ENV['KALTURA_PARTNER_SECRET'], ENV['KALTURA_CAT_ID'], ENV['KALTURA_ROOT_CATEGORY_PATH'], cat_name, entry_name, meeting_id, full_recording_file)
  end

  def ffmpeg_x11_grab(ffmpeg_bin,resolution, frame_rate, x_display, duration, recording_file)

    ffmpeg_x11grab_command=ffmpeg_bin + ' -s ' + resolution + ' -framerate ' + frame_rate.to_s + ' -f x11grab -i :' + x_display.to_s + ' -t ' + duration.to_s + ' -vf "crop=in_w:in_h-147" -y ' + recording_file.shellescape
    @logger.info('X11grab COMMAND IS: ' + ffmpeg_x11grab_command)
    
    system ffmpeg_x11grab_command
    if $?.exitstatus != 0
      @logger.error('ffmpeg x11grab command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def ffmpeg_detect_scene_start_time(ffmpeg_bin,recording_file,scene_number)
    ffmpeg_scene_command=ffmpeg_bin + " -i " + recording_file.shellescape + " -filter:v \"select='gt(scene,0.4)',showinfo\"  -frames:v " + scene_number.to_s + " -f null  - 2>&1|grep pts_time|sed 's/.*pts_time:\\([0-9.]*\\).*/\\1/'"
    @logger.info('scene COMMAND IS: ' + ffmpeg_scene_command)
    first_scene, stdeerr, status = Open3.capture3(ffmpeg_scene_command)
    # because of our sed here, status.success? will always be true so need to insepct the value further.
    if !first_scene.empty?
      first_scene=first_scene.delete!("\n").to_f
      if !first_scene.is_a? Numeric
        @logger.error('ffmpeg scene detection command failed :(')
        return false
      end
    end
    return first_scene
  end

  def ffmpeg_trim_video(ffmpeg_bin, recording_file, start_time, duration, output_file)
    ffmpeg_trim_command=ffmpeg_bin + " -i " + recording_file.shellescape + " -ss " + start_time.to_s + " -t " + duration.to_s + " -c copy -strict -2 -an -y " + output_file.shellescape	
    @logger.info("Trim COMMAND IS: " + ffmpeg_trim_command)
    system ffmpeg_trim_command 
    if $?.exitstatus != 0
      @logger.error('ffmpeg trim command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def ffmpeg_merge_vid_and_aud_tracks(ffmpeg_bin, vid_file, aud_file, output_file)
    ffmpeg_merge_command=ffmpeg_bin + " -i " + vid_file.shellescape + " -i " + aud_file.shellescape + " -c copy -y " + output_file.shellescape

    @logger.info("Merge COMMAND IS: " + ffmpeg_merge_command)
    system ffmpeg_merge_command 
    if $?.exitstatus != 0
      @logger.error('ffmpeg audio and video merge command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def ingest_to_kaltura(base_endpoint,partner_id, secret, parent_cat_id, full_cat_path, cat_name, entry_name, meeting_id, vid_file_path)
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
    entry.description = "AC original ID: " + meeting_id
    entry.tags = meeting_id
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
