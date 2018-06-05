#!/usr/bin/ruby
require 'nokogiri'
require 'kaltura'
include Kaltura
def output_data(connect,sco_id)
        response = connect.sco_info(sco_id: sco_id)
        folder_id = response.at_xpath('//sco//@folder-id')
        fresponse = connect.sco_info(sco_id: folder_id)
        folder_name = fresponse.at_xpath('//sco//name').text
        print sco_id +',"'+folder_name.tr(',', '').tr('(','').tr(')','') + '","' + response.at_xpath('//sco//name').text.tr(',', '').tr('(','').tr(')','') + '",' 
        print response.at_xpath('//sco//url-path').text.tr('/', '') + "\n"
end

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
  #entry = KalturaMediaEntry.new()
  #entry.media_type = KalturaMediaType::VIDEO
  entry = KalturaBaseEntry.new()
  entry.name = entry_name
  type = KalturaEntryType::AUTOMATIC
  entry.description = "AC original ID: " + meeting_id
  entry.tags = meeting_id
  entry.categories=full_cat_path + ">" +cat_name

  #results = client.media_service.add(entry)
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
  #end
end

if ARGV.length < 4
  puts "Usage: " + __FILE__ + "<meeting id> </path/to/vid/file> </path/to/slides/metadata/xml> </path/to/images/dir>"
  exit 1
end


base_endpoint='https://www.kaltura.com'
partner_id=2053461
secret="4077d41b1213063238f44162866ed809"
parent_cat_id=91110522
full_cat_path="Mediaspace>site>galleries>PSU>Adobe Connect"
cat_name="slide_test"

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

