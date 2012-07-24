# encoding: utf-8
require 'open-uri'
require 'json'
require 'rss/maker'

require 'sinatra'
require 'memcachier'
require 'dalli'

VERSION = '0.1'
RSS_VERSION = '2.0'

APP_URL = 'http://tabrss.heroku.com/'
TAB_API_BASE = 'http://tab.do/api/1/'

get '/' do
  'This is test to distribute rss for tab'
end

# Popular rss
get '/popular.rdf' do
  content_type 'application/xml'

  cache_key = "#{VERSION}/popular"
  cache = Dalli::Client.new(nil, expires_in: 120, compress: true)
  resp = cache.get(cache_key) rescue nil
  if resp.nil?
    url = "#{TAB_API_BASE}items/popular.json"
    logger.info("url: #{url}")
    hash = JSON.parse(open(url).read)

    resp = RSS::Maker.make(RSS_VERSION) do |m|
      m.channel.title = "tab 人気のアイテム"
      m.channel.description = "tab で今人気のアイテムを紹介"
      m.channel.link = "#{APP_URL}popular.rdf"
      hash['items'].each do |item|
        rss_item = m.items.new_item
        rss_item.title = item['title']
        rss_item.link = item['site_url']
        rss_item.date = item['created_at']
        rss_item.description = item['description']
        rss_item.enclosure.url = item['image_urls'][0]['normal_L']
        rss_item.enclosure.type = 'image/jpeg'
        rss_item.enclosure.length = 0
      end
    end

    cache.set(cache_key, resp) rescue nil
  end
  resp.to_s
end
