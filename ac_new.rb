#!/usr/bin/ruby
require 'json'
require 'selenium-webdriver'
gem 'test-unit'
require 'test/unit'
require 'open3'
require 'shellwords'
require 'kaltura'
require 'logger'
require 'fileutils'

include Kaltura

class Vconn1 < Test::Unit::TestCase
  Max_Upload_Size = 1.5*1024*1024*1024
  def setup
    @logger = Logger.new(STDOUT)
    @logger.level = Logger::INFO

    @logger.formatter = proc do |severity, datetime, _progname, msg|
      fileLine = ''
      caller.each do |clr|
        unless /\/logger.rb:/ =~ clr
          fileLine = clr
          break
        end
      end
      fileLine = fileLine.split(':in `', 2)[0]
      fileLine.sub!(/:(\d)/, '(\1')
      "#{datetime}: #{severity} #{fileLine}): #{msg}\n"
    end

    @profile = Selenium::WebDriver::Firefox::Profile.new
    @profile['plugin.state.flash'] = 2
    @profile['plugins.flashBlock.enabled'] = 0
    @profile['default_content_settings.state.flash'] = 1
    @profile['RunAllFlashInAllowMode'] = 1
    @profile['AllowOutdatedPlugins'] = 1
    options = Selenium::WebDriver::Firefox::Options.new
    @caps = Selenium::WebDriver::Remote::Capabilities.firefox(firefox_profile: @profile)

    @base_url = ENV['AC_ENDPOINT']
    @driver = Selenium::WebDriver.for :firefox, desired_capabilities: @caps
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

    mandatory_env_vars = %w[OUTDIR MEETING_ID MEETING_NAME CATEGORY_NAME AC_USERNAME AC_PASSWD X_SERVER_DISPLAY_NUM]

    mandatory_env_vars.each do |mandatory_var|
      if !ENV[mandatory_var] || ENV[mandatory_var].empty?
        @logger.error('Missing ENV var ' + mandatory_var + ':( Make sure you export it.')
        return false
      end
    end

    out_dir = ENV['OUTDIR'] + '/'
    # let's strip spaces just to be on the safe side
    meeting_id = ENV['MEETING_ID'].strip
    entry_name = ENV['MEETING_NAME']
    cat_name = ENV['CATEGORY_NAME']
    ac_username = ENV['AC_USERNAME']
    ac_passwd = ENV['AC_PASSWD']
    ac_html = ENV['AC_HTML_VIEW'] || 'true'
    duration = ENV['DURATION']
    x_display = ENV['X_SERVER_DISPLAY_NUM']
    ffmpeg_bin = ENV['FFMPEG_BIN'] || 'ffmpeg'
    ffprobe_bin = ENV['FFPROBE_BIN'] || 'ffprobe'

    resolution = '1280x720'
    frame_rate = '30'
    audio_file = out_dir + meeting_id + '.mp3'
    recording_file = out_dir + meeting_id + '.mkv'

    audio_track_exists = true
    basedir = File.dirname(__FILE__)
    @logger.info(basedir + '/get_ac_audio.sh ' + meeting_id)
    system basedir + '/get_ac_audio.sh ' + meeting_id
    if ($?.exitstatus != 0) || !File.exist?(audio_file)
      @logger.warn('Failed to obtain audio file :(')
      audio_track_exists = false
    end

    if duration.to_f > 0
        dur_sec = duration.to_f
   elsif audio_track_exists
      # get duration from the MP3 file, we'll use that to determine how long ffmpeg should be recording for
      dur_sec, stdeerr, status = Open3.capture3(ffprobe_bin + ' -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 ' + audio_file.shellescape)
      dur_sec = dur_sec.delete!("\n")
      if !status.success?
        log.error('Failed to get audio track duration. Exited with ' + $?.exitstatus.to_s + ':(')
        return false
      end
    else
      log.error('Failed to get duration from audio track or XML metadata :(')
      return false
    end

    # Add a 15 seconds buffer
    extra_duration = dur_sec.to_f + 15

    if ENV['AC_LOGIN_REQUIRED'] === 'true'
      @driver.get(@base_url + '/system/login?logintype=oldstyle&next=/admin')
      @driver.find_element(:id, 'name').send_keys ac_username
      @driver.find_element(:id, 'pwd').send_keys ac_passwd
      @driver.find_element(:id, 'login-button').click
    end
    @driver.get(@base_url + '/' + meeting_id + '?launcher=false&fcsContent=true&pbMode=normal&html-view=' + ac_html)
    # html player requires a few extra actions after navigating to the page
    if ac_html == 'true'
      @driver.switch_to.frame('html-meeting-frame')
      wait = Selenium::WebDriver::Wait.new(timeout: 60)
      wait.until { @driver.find_element(:id, 'play-recording-shim-button') }.click
      wait.until { @driver.find_element(:id, 'switch-to-classic-view-notifier_0') }.click
      @driver.execute_script 'document.querySelector("body").style.cursor = "none"'
    end

	# this PID file is created by capture_audio.sh
	steam_pid = out_dir + '/steam_' + meeting_id + '.pid' 
    # FFmpeg magic
    # record X11's display
    if !ffmpeg_x11_grab(ffmpeg_bin, meeting_id, resolution, frame_rate, x_display, extra_duration.to_s, recording_file, steam_pid)
      return false
    end


    if File.exist?(recording_file)
      @logger.info('Final output saved to: ' + recording_file + ' :)')
    else
      @logger.error("Something failed and I couldn't find a " + recording_file + ' to process :(')
      return false
    end

    # verify the Kaltura params are set before attempting to ingest to Kaltura
    kaltura_mandatory_vars = %w[KALTURA_BASE_ENDPOINT KALTURA_PARTNER_ID KALTURA_PARTNER_SECRET SCO_ID]

    kaltura_mandatory_vars.each do |mandatory_var|
      if !ENV[mandatory_var] || ENV[mandatory_var].empty?
        @logger.warn('Skipping Kaltura ingestion, missing ENV var ' + mandatory_var)
        return
      end
    end

    sco_id = ENV['SCO_ID']

    client = init_client(ENV['KALTURA_BASE_ENDPOINT'], ENV['KALTURA_PARTNER_ID'], ENV['KALTURA_PARTNER_SECRET'])
    ingest_to_kaltura(client, entry_name, meeting_id, sco_id, recording_file)
  end

  def ffmpeg_x11_grab(ffmpeg_bin, meeting_id, resolution, frame_rate, x_display, duration, recording_file, steam_pid)
	my_sink = nil
	# wait for the capture_audio magic to end so that we'll have pulse audio sinks
	while ! File.exist?(steam_pid)
		sleep 0.1 
	end
	my_sink, stdeerr, status = Open3.capture3("pacmd list-sources | grep -PB 1 \"" + meeting_id + ".*monitor>\" |  head -n 1 | perl -pe 's/.* //g'")
	my_sink = my_sink.delete!("\n")
	my_sink = my_sink.to_i
	if ! my_sink.is_a? Numeric
		return false
	end

	# override duration for faster testing/debugging 
    #duration = 120
    ffmpeg_x11grab_command = ffmpeg_bin + ' -s ' + resolution + ' -framerate ' + frame_rate.to_s + ' -f x11grab -i :' + x_display.to_s + ' -f pulse -i ' + my_sink.to_s + '  -c:v libx264  -acodec libmp3lame -crf 0 -preset ultrafast -t ' + duration.to_s + ' -vf "crop=in_w:in_h-147" -y ' + recording_file.shellescape
    @logger.info('X11grab command is: ' + ffmpeg_x11grab_command)

    system ffmpeg_x11grab_command 
		rc=$?
		# delete the PID capture_audio.sh creates since we're done with it
		File.delete(steam_pid) if File.exist?(steam_pid)
    if rc.exitstatus != 0
      @logger.error('ffmpeg x11grab command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def ffmpeg_detect_scene_start_time(ffmpeg_bin,recording_file,scene_number)
    ffmpeg_scene_command=ffmpeg_bin + " -i " + recording_file.shellescape + " -filter:v \"select='gt(scene,0.3)',showinfo\"  -frames:v " + scene_number.to_s + " -f null  - 2>&1|grep pts_time|sed 's/.*pts_time:\\([0-9.]*\\).*/\\1/'"

    @logger.info('Scene command is: ' + ffmpeg_scene_command)
    first_scene, stdeerr, status = Open3.capture3(ffmpeg_scene_command)
    # because of our sed here, status.success? will always be true so need to insepct the value further.
    if first_scene.empty?
      @logger.error('ffmpeg scene detection command failed to detect first scene time :(')
      return false
    end
    first_scene = first_scene.delete!("\n")
    first_scene = first_scene.to_f
    if !first_scene.is_a? Numeric
      @logger.error('ffmpeg scene detection command came back with unexpected output: ' + first_scene + ' :(')
      return false
    end

    @logger.info('First scene detected as: ' + first_scene.to_s)
    return first_scene
  end

  def ffmpeg_trim_video(ffmpeg_bin, recording_file, start_time, output_file)
    ffmpeg_trim_command = ffmpeg_bin + " -i " + recording_file.shellescape + " -ss " + start_time.to_s +  " -c copy -y " + output_file.shellescape	
    @logger.info('Trim command is: ' + ffmpeg_trim_command)
    system ffmpeg_trim_command
    if $?.exitstatus != 0
      @logger.error('ffmpeg trim command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def ffmpeg_merge_vid_and_aud_tracks(ffmpeg_bin, vid_file, aud_file, output_file)
    ffmpeg_merge_command = ffmpeg_bin + ' -i ' + vid_file.shellescape + ' -i ' + aud_file.shellescape + ' -c copy -y ' + output_file.shellescape

    @logger.info('Merge command is: ' + ffmpeg_merge_command)
    system ffmpeg_merge_command
    if $?.exitstatus != 0
      @logger.error('ffmpeg audio and video merge command exited with ' + $?.exitstatus.to_s + ':(')
      return false
    end
    return true
  end

  def init_client(base_endpoint, partner_id, secret)
    config = KalturaConfiguration.new()
    config.service_url = base_endpoint
    client = KalturaClient.new(config)
    client.ks = client.session_service.start(
      secret,
      nil,
      Kaltura::KalturaSessionType::ADMIN,
      partner_id,
      nil,
      'disableentitlement'
    )

    return client
  end

  def get_or_create_metadata_profile_id(client, metadata_profile_sys_name)
    metadata_profile_filter = KalturaMetadataProfileFilter.new()
    metadata_profile_filter.system_name_equal = metadata_profile_sys_name
    response = client.metadata_profile_service.list(metadata_profile_filter)

    if response.total_count > 0
      return response.objects[0].id
    end

    # if this metadata profile does not exist - create it.
    metadata_profile = KalturaMetadataProfile.new()
    metadata_profile.name = 'Adobe Connect Migration'
    metadata_profile.system_name = metadata_profile_sys_name
    metadata_profile.metadata_object_type = Kaltura::KalturaMetadataObjectType::ENTRY
    xsd = File.read(File.dirname(__FILE__) + File::SEPARATOR + 'ac_migration.xsd')

    metadata_profile = client.metadata_profile_service.add(metadata_profile, xsd)
    if metadata_profile
      return metadata_profile.id
    end

    return false
  end

  def create_category_association(client, parent_cat_id, full_cat_path, cat_name, entry_id)
    # check whether category already exists
    filter = KalturaCategoryFilter.new()
    filter.full_name_equal = full_cat_path + '>' + cat_name
    pager = KalturaFilterPager.new()
    results = client.category_service.list(filter, pager)
    ## if not, create it
    category_id = false
    if results.total_count == 0
      category = KalturaCategory.new()
      category.parent_id = parent_cat_id
      category.name = cat_name
      begin
        results = client.category_service.add(category)
        @logger.info('Created category: ' + cat_name + ', cat ID: ' + results.id.to_s)
        category_id = results.id
      rescue Kaltura::KalturaAPIError => e
        @logger.error("Exception Class: #{e.class.name}")
        @logger.error("Exception Message: #{e.message}")
        # enable to get a BT
        # @logger.info("Exception Message: #{ e.backtrace }")
      end
    else
      category_id = results.objects[0].id
    end

    category_entry = KalturaCategoryEntry.new()
    category_entry.entry_id = entry_id
    category_entry.category_id = category_id
    begin
      response = client.category_entry_service.add(category_entry)
    rescue Kaltura::KalturaAPIError => e
      @logger.error("Exception Class: #{e.class.name}")
      @logger.error("Exception Message: #{e.message}")
    end
  end

  def ingest_to_kaltura(client, entry_name, meeting_id, sco_id, vid_file_path)
    upload_token = KalturaUploadToken.new()

    results = client.upload_token_service.add(upload_token)
    upload_token_id = results.id

    if (File.size(vid_file_path) > Max_Upload_Size)
    # chunked upload is required in this case.
	dir=File.dirname(vid_file_path)
	basename=File.basename(vid_file_path,'.mkv')

	chunked_dir=File.join(dir, basename+'_chunked')

	if File.exist?(chunked_dir)
		FileUtils.rm_rf(chunked_dir)
	end

	Dir.mkdir(chunked_dir)
	system('split -d -b 500m ' + vid_file_path + ' ' + File.join(chunked_dir, 'piece'))

	files = Dir.glob(chunked_dir + '/piece*')

	i = 0
	resume_at = 0
	while i<files.count do
        	resume = true
        	if i==0
                	resume = false
        	end

        	final_chunk = false
        	if i == files.count-1
                	final_chunk = true
        	end
		begin
        		results = client.upload_token_service.upload(upload_token_id, File.open(File.join(chunked_dir,'piece' + format('%02d', i.to_s))), resume, final_chunk, resume_at)
        		resume_at += File.size(File.join(chunked_dir,'piece' + format('%02d', i.to_s)))
        		i += 1
		rescue Kaltura::KalturaAPIError => e
			@logger.error("Exception Class: #{e.class.name}")
			@logger.error("Exception Message: #{e.message}")
			break
		end
	end
	# if the DEBUG_MODE flag is not set to 1 - delete the chunked directory at the end of the process
        if !ENV['AC_TOOL_DEBUG_MODE']
		FileUtils.rm_rf(chunked_dir)
    	end 
    else
        file_data = File.open(vid_file_path)
        resume = false
        final_chunk = true
        resume_at = -1
	
	begin
                results = client.upload_token_service.upload(upload_token_id, file_data, resume, final_chunk, resume_at)
        rescue Kaltura::KalturaAPIError => e
                @logger.error("Exception Class: #{e.class.name}")
                @logger.error("Exception Message: #{e.message}")
        end
    end

    resource = KalturaUploadedFileTokenResource.new()
    resource.token = upload_token_id

    filter = KalturaMediaEntryFilter.new()
    filter.reference_id_equal = sco_id
    filter.status_equal = KalturaEntryStatus::READY
    existing_entries = client.media_service.list(filter)

    if ENV['KALTURA_ENABLE_REPLACEMENT'] && existing_entries.total_count > 0
        entry_id = existing_entries.objects[0].id
        replace_existing_entry(client, entry_id, resource)
    else
        add_entry_as_new(client, entry_name, meeting_id, sco_id, resource)
    end
  end

  def add_entry_as_new(client, entry_name, meeting_id, sco_id, resource)
    entry = KalturaMediaEntry.new()
    entry.media_type = KalturaMediaType::VIDEO
    entry.name = entry_name
    entry.reference_id = sco_id
    entry.tags = meeting_id

    if ENV['USER_ID']
      entry.user_id = ENV['USER_ID']
    end

    if ENV['DESCRIPTION']
      entry.description = ENV['DESCRIPTION']
    end

    results = client.media_service.add(entry)
    entry_id = results.id

    results = client.media_service.add_content(entry_id, resource)
    if !defined? results.id
      @logger.error("media_service.add_content() failed:(")
      return false
    end
    @logger.info("Created entry ID: " + results.id)
    if ENV['KALTURA_ROOT_CATEGORY_ID'] && ENV['KALTURA_ROOT_CATEGORY_PATH']
      create_category_association(client, ENV['KALTURA_ROOT_CATEGORY_ID'], ENV['KALTURA_ROOT_CATEGORY_PATH'], ENV['CATEGORY_NAME'], entry_id)
    end

    if ENV['ORIG_CREATED_AT'] && ENV['KALTURA_METADATA_SYSTEM_NAME']
      # retrieve metadata profile ID
      metadata_profile_id = get_or_create_metadata_profile_id(client, ENV['KALTURA_METADATA_SYSTEM_NAME'])
      if metadata_profile_id
        metadata = sprintf(ENV['KALTURA_METADATA_XML'], {:orig_created_at => ENV['ORIG_CREATED_AT']})
        begin
          client.metadata_service.add(metadata_profile_id, Kaltura::KalturaMetadataObjectType::ENTRY, entry_id, metadata)
        rescue Kaltura::KalturaAPIError => e
          @logger.error("Error occurred creating orig_created_at custom metadata for entry #{entry_id}")
          @logger.error("Exception Class: #{ e.class.name }")
          @logger.error("Exception Message: #{ e.message }")
          # enable to get a BT
          # @logger.info("Exception Message: #{ e.backtrace }")
        end
      end
    end

    return results.id
  end

  def replace_existing_entry(client, entry_id, resource)
    @logger.info("Replacing content for entry " + entry_id)
    begin
    	results = client.media_service.update_content(entry_id, resource)
    rescue Kaltura::KalturaAPIError => e
	@logger.error("Exception Class: #{e.class.name}")
        @logger.error("Exception Message: #{e.message}")
    end

    return entry_id
  end

  def element_present?(how, what)
    @driver.find_element(how, what)
    true
  rescue Selenium::WebDriver::Error::NoSuchElementError
    false
  end

  def alert_present?
    @driver.switch_to.alert
    true
  rescue Selenium::WebDriver::Error::NoAlertPresentError
    false
  end

  def verify
    yield
  rescue Test::Unit::AssertionFailedError => ex
    @verification_errors << ex
  end

  def close_alert_and_get_its_text(_how, _what)
    alert = @driver.switch_to.alert()
    alert_text = alert.text
    if @accept_next_alert
      alert.accept()
    else
      alert.dismiss()
    end
    alert_text
  ensure
    @accept_next_alert = true
  end
end
