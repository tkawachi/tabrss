# encoding: utf-8
require 'open-uri'
require 'json'
require 'rss/maker'

require 'sinatra'
require 'memcachier'
require 'dalli'

VERSION = '0.1'
RSS_VERSION = '2.0'

USE_CACHE = true
CACHE_VERSION = '0.2'
CACHE_EXPIRES_IN = 10

APP_URL = 'http://tabrss.heroku.com'
TAB_URL = 'http://tab.do'

API_TITLES = [
    [%r'/items/popular.json$', 'tab 人気のアイテム'],
    [%r'/items/latest.json$', 'tab 最新のアイテム'],
    [%r'/users/\d+/items.json$', 'tab ユーザのアイテム'],
    [%r'/streams/\d+/items.json$', 'tab 内のアイテム'],
    [%r'/areas/\d+/items.json$', 'tab エリア内のアイテム']
]

def size_of_image(url)
  # HEAD request にすれば速くなる
  open(url).read.size
end

def items_api_to_rdf(cache_key, api_url, title, description, link)
  if USE_CACHE
    cache = Dalli::Client.new(nil, expires_in: CACHE_EXPIRES_IN, compress: true)
    resp = cache.get(cache_key) rescue nil
  else
    resp = nil
  end
  if resp.nil?
    logger.info("url: #{api_url}")
    hash = JSON.parse(open(api_url).read)
    unless hash['items']
      return "items が見つかりません。#{api_url} はアイテム一覧 API じゃないのでは？"
    end

    resp = RSS::Maker.make(RSS_VERSION) do |m|
      m.channel.title = title
      m.channel.description = description || title
      m.channel.link = link
      hash['items'].each do |item|
        rss_item = m.items.new_item
        rss_item.title = item['title']
        rss_item.link = item['site_url']
        rss_item.date = item['created_at']
        image_url = item['image_urls'][0]['normal_L'] rescue nil
        if image_url
          rss_item.description = "<img src=\"#{image_url}\" style=\"float:left;\">#{item['description']}"
        else
          rss_item.description = item['description']
        end
      end
    end

    if USE_CACHE
      cache.set(cache_key, resp) rescue nil
    end
  end

  content_type 'application/xml'
  resp.to_s
end

get '/' do
  popular_rss = "#{APP_URL}/api/1/items/popular.json"
  latest_rss = "#{APP_URL}/api/1/items/latest.json"
  user_rss = "#{APP_URL}/api/1/users/57/items.json"
  shibuya_rss = "#{APP_URL}/api/1/areas/6/items.json"
  <<-EOS
<!DOCTYPE html>
<meta charset="utf-8">
<title>RSS for tab</title>
<a href="https://github.com/tkawachi/tabrss"><img style="position: absolute; top: 0; right: 0; border: 0;" src="https://s3.amazonaws.com/github/ribbons/forkme_right_green_007200.png" alt="Fork me on GitHub"></a>
<h1>RSS for tab</h1>
このプログラムは <a href="#{TAB_URL}">tab.do</a> で提供されているアイテム一覧 API を RSS に変換して表示します。
<a href="http://tonchidot.github.com/tab-api-docs/api/index.html">Items API</a>の中で JSON のトップ要素として
items が返ってくる API を変換することができます。
tab API のホスト名部分を #{APP_URL} に変更してリクエストしてください。
<p>
トップに items がない API を叩くとエラーになります ^^;
<p>
<a href="http://www.google.com/reader/view/">Google Reader</a> に登録すると
<a href="http://itunes.apple.com/jp/app/flipboard-anatanososharunyusumagajin/id358801284?mt=8">Flipboard</a>
で眺めたりすることができます。
<p>
<ul>
<li> 人気のアイテム: <a href="#{popular_rss}">#{popular_rss}</a>
<li> 最新のアイテム: <a href="#{latest_rss}">#{latest_rss}</a>
<li> フォローしているアイテム (57 の部分は私の user id です。
  自分の user id は tab のプロファイル画面を開いて URL を確認してください):
  <a href="#{user_rss}">#{user_rss}</a>
<li> 渋谷のアイテム (6 の部分は渋谷の area id です。
  他のエリアの id は http://tab.do/api/1/areas を見ればわかるかも?):
  <a href="#{shibuya_rss}">#{shibuya_rss}</a>
</ul>
  EOS
end

get '/version' do
  VERSION
end

def find_title(path)
  API_TITLES.each do |title_pair|
    regex = title_pair[0]
    title = title_pair[1]
    if regex =~ path
      return title
    end
  end
  return 'tab'
end

get '/api/*' do
  path = request.path_info
  # Specify format as JSON
  path += ".json" unless path.end_with?(".json")
  url = "#{TAB_URL}#{path}"
  cache_key = "#{CACHE_VERSION}#{url}"
  title = find_title(path)
  link = "#{APP_URL}#{path}"
  items_api_to_rdf(cache_key, url, title, nil, link)
end