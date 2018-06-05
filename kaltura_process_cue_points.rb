#!/usr/bin/ruby
require 'nokogiri'
require 'kaltura'
include Kaltura

def process_slides(xml)
  slides_array=[]
  xml.xpath('//section').each do |section|
    #position=section.at_xpath('@position')
    content=section.at_xpath('content').text
    title=section.at_xpath('title').text
    my_slide={:title=>title,:content=>content}
    slides_array.push(my_slide)
  end
  return slides_array
end

def ingest_to_kaltura(client,base_endpoint,partner_id, secret, parent_cat_id, full_cat_path, cat_name, entry_name, meeting_id, vid_file_path)

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
	      puts("Created category: " + cat_name + ", cat ID: "+results.id)
  end
  upload_token = KalturaUploadToken.new()

  results = client.upload_token_service.add(upload_token)
  upload_token_id=results.id

  file_data = File.open(vid_file_path)
  resume = false
  final_chunk = true
  resume_at = -1

  results = client.upload_token_service.upload(upload_token_id, file_data, resume, final_chunk, resume_at)
  entry = KalturaBaseEntry.new()
  entry.name = entry_name
  type = KalturaEntryType::AUTOMATIC
  entry.description = "AC original ID: " + meeting_id
  entry.tags = meeting_id
  entry.categories=full_cat_path + ">" +cat_name

  results = client.base_entry_service.add(entry,type)

  entry_id = results.id
  resource = KalturaUploadedFileTokenResource.new()
  resource.token = upload_token_id

  results = client.base_entry_service.add_content(entry_id, resource)
  if !defined? results.id
    puts("base_entry_service.add_content() failed:(")
    return false
  end
  puts("Uploaded " + vid_file_path + ", entry ID: " + results.id)
  return results.id
end  

def ingest_slides_to_kaltura(client, entry_id, slides_metatdata_array, images_path)
  img_files=Dir[images_path + "/**/*.{jpg}"]
  img_files.each do |image_path|
    parts=(File.basename image_path).split("_")
    seq=parts[0].to_i 
    time=parts[1].chomp('.jpg')
    round_ms_time=(time.to_f.round * 1000)
    
    if ! defined? slides_metadata_array or !slides_metatdata_array[seq]
      slide_system_name="slide " + seq.to_s 
      slide_title=slide_system_name
      slide_content=nil
    else
      slide_title=slides_metatdata_array[seq][:title]
      slide_system_name="slide " + seq.to_s + ":" + slide_title
      slide_content=slides_metatdata_array[seq][:content]
    end

    cue_point = KalturaThumbCuePoint.new()
    cue_point.entry_id = entry_id
    cue_point.start_time = round_ms_time
    cue_point.system_name = slide_system_name 
    cue_point.title = slide_title
    cue_point.description = slide_content
    cue_res = client.cue_point_service.add(cue_point)
    timed_thumb_asset = KalturaTimedThumbAsset.new()
    timed_thumb_asset.cue_point_id=cue_res.id
    thumb_asset_res=client.thumb_asset_service.add(entry_id, timed_thumb_asset)
    puts thumb_asset_res.inspect
    file_data = File.open(image_path)
    results = client.thumb_asset_service.add_from_image(entry_id, file_data)
    puts results.inspect
    thumb_id = results.id
    cue_point.asset_id = thumb_id

    results = client.cue_point_service.update(cue_res.id, cue_point)
    puts results.inspect
    
  end
end

if ARGV.length < 5
  puts "Usage: " + __FILE__ + "<meeting id> </path/to/vid/file> </path/to/slides/metadata/xml> </path/to/images/dir> <entry name>"
  exit 1
end


base_endpoint=ENV['KALTURA_BASE_ENDPOINT']
partner_id=ENV['KALTURA_PARTNER_ID']
secret=ENV['KALTURA_PARTNER_SECRET']
parent_cat_id=ENV['KALTURA_CAT_ID']
full_cat_path=ENV['KALTURA_ROOT_CATEGORY_PATH']
cat_name="Test Cat"

meeting_id=ARGV[0]
vid_file_path=ARGV[1]
if File.exist?(ARGV[2])
  xml=File.open(ARGV[2]).read
  slides_metatdata_array=process_slides(Nokogiri::XML(xml))
else
  slides_metadata_array=[]
end
imgs_dir=ARGV[3]
entry_name=ARGV[4]

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
entry_id=ingest_to_kaltura(client,base_endpoint,partner_id, secret, parent_cat_id, full_cat_path, cat_name, entry_name, meeting_id, vid_file_path)
ingest_slides_to_kaltura(client, entry_id, slides_metatdata_array, imgs_dir)

