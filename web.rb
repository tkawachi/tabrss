# encoding: utf-8
require 'open-uri'
require 'json'
require 'rss/maker'

require 'sinatra'
require 'memcachier'
require 'dalli'

VERSION = '0.1'
USE_CACHE = false
CACHE_VERSION = '0.2'
CACHE_EXPIRES_IN = 300
PAGING_LIMIT = 30
RSS_VERSION = '2.0'

APP_URL = 'http://tabrss.heroku.com/'
TAB_API_BASE = 'http://tab.do/api/1/'

def size_of_image(url)
  # HEAD request にすれば速くなる
  open(url).read.size
end

def items_api_to_rdf(cache_key, api_url, title, description, link)
  content_type 'application/xml'

  if USE_CACHE
    cache = Dalli::Client.new(nil, expires_in: CACHE_EXPIRES_IN, compress: true)
    resp = cache.get(cache_key) rescue nil
  else
    resp = nil
  end
  if resp.nil?
    logger.info("url: #{api_url}")
    hash = JSON.parse(open(api_url).read)

    resp = RSS::Maker.make(RSS_VERSION) do |m|
      m.channel.title = title
      m.channel.description = description
      m.channel.link = link
      hash['items'].each do |item|
        rss_item = m.items.new_item
        rss_item.title = item['title']
        rss_item.link = item['site_url']
        rss_item.date = item['created_at']
        image_url = item['image_urls'][0]['original'] rescue nil
        if image_url
          rss_item.description = "<img src=\"#{image_url}\" style=\"float:left;\">#{item['description']}"
        else
          rss_item.description = item['description']
        end
        #begin
        #  rss_item.enclosure.url = image_url
        #  rss_item.enclosure.type = 'image/jpeg'
        #  rss_item.enclosure.length = size_of_image(image_url)
        #rescue
        #  # Do nothing
        #end
      end
    end

    if USE_CACHE
      cache.set(cache_key, resp) rescue nil
    end
  end
  resp.to_s
end

get '/' do
  'This is test to distribute rss for tab'
end

# Popular rss
get '/popular.rdf' do
  items_api_to_rdf(
      "#{CACHE_VERSION}/popular",
      "#{TAB_API_BASE}items/popular.json?limit=#{PAGING_LIMIT}",
      "tab 人気のアイテム",
      "tab で今人気のアイテムを紹介",
      "#{APP_URL}popular.rdf"
  )
end

get '/latest.rdf' do
  items_api_to_rdf(
      "#{CACHE_VERSION}/latest",
      "#{TAB_API_BASE}items/latest.json?limit=#{PAGING_LIMIT}",
      "tab 最新のアイテム",
      "tab で今投稿されたばかりのアイテムを紹介",
      "#{APP_URL}latest.rdf"
  )
end