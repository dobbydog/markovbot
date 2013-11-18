# -*- coding: utf-8 -*-

module MarkovBot
  require 'MeCab'
  require 'twitter'
  require 'mongo'
  require 'nokogiri'
  require 'open-uri'
  
  TAGGER = MeCab::Tagger.new("-Owakati")
  
  module WordCollection
    module Common
      def initialize(collection)
        @source = collection
      end
      attr_reader :source
      
      def build_sentence(query, interrogative = false)
        seed = search(query)
        return nil if seed.nil?
        second = seed["second"]
        third = seed["third"]
        out = query["first"] + second
        while third != "EOS"
          out += third
          query = {"first" => second, "second" => third}
          seed = search(query)
          break if seed.nil?
          second = third
          third = seed["third"]
        end
        out.gsub(/^BOS/, '').gsub(/EOS$/, '')
      end
      
      def build_sentence_reverse(query)
        seed = search(query)
        return nil if seed.nil?
        first = seed["first"]
        second = seed["second"]
        third = seed["third"]
        out = second + third
        while first != "BOS"
          out = first + out
          query = {"second" => first, "third" => second}
          seed = search(query)
          break if seed.nil?
          second = first
          first = seed["first"]
        end
        
        out.gsub(/^BOS/, '').gsub(/EOS$/, '')
      end
      
      def search; end
      def save; end
    end
    
    class Mongo
      include Common
      
      def search(query)
        @source.find(query).to_a.sample
      end
      
      def save(doc)
        if @source.find_one(doc).nil? then
          @source.save(doc)
          puts "saved"
        else
          puts "skipped"
        end
      end
    end
    
    class ArrayList
      include Common
      
      def search(query)
        res_array = Array.new
        @source.each do |s|
          res_array << s if s == s.merge(query)
        end
        res_array.sample
      end
    end
    
    class << self
      def make_al_from_search(query)
        esc_query = URI.escape(query)
        uri = "http://www.bing.com/search?q=" + esc_query
        result_doc = Nokogiri::HTML(open(uri))
        news_txt = result_doc.css(".sa_cc > p")
        dic = Array.new
        news_txt.each do |n|
          dic += build_collection(n.text)
        end
        ArrayList.new(dic)
      end
      
      def make_al_from_array(arr)
        dic = Array.new
        arr.each do |n|
          dic += build_collection(n)
        end
        ArrayList.new(dic)
      end
      
      def build_collection(text)
        collection = Array.new
        TAGGER.parse("BOS" + text + "EOS").force_encoding("UTF-8").split(" ").each_cons(3) do |a|
          collection << {"first" => a[0], "second" => a[1], "third" => a[2]}
        end
        collection
      end
    end
  end
  
  class Twtr
    def initialize(conf)
      twconf = conf['twitter']
      dbconf = conf['mongo']
      @botconf = conf['bot']
      
      Twitter.configure do |c|
        c.consumer_key = twconf['consumer_key']
        c.consumer_secret = twconf['consumer_secret']
        c.oauth_token = twconf['oauth_token']
        c.oauth_token_secret = twconf['oauth_token_secret']
      end
      
      conn = Mongo::Connection.new
      db = conn.db(dbconf['db'])
      words_col = db.collection(dbconf['words_collection'])
      @words = WordCollection::Mongo.new(words_col)
      @log = db.collection(dbconf['log_collection'])
    end
    
    def reply
      replied = @log.find_one(:name => 'replied')['id']
      Twitter.mentions(:since_id => replied, :count => 20).reverse.each do |r|
        node = TAGGER.parseToNode(r[:text].gsub(/@[a-zA-Z0-9_]+ ?/, '')).next
        nouns = Array.new
        while node do
          surface = node.surface.force_encoding("utf-8")
          feature = node.feature.force_encoding("utf-8").split(",")
          nouns << surface if feature[0] =~ /(名詞|動詞|形容詞)/
          node = node.next
        end
        result = nil
        while !nouns.empty? do
          seed = nouns.slice!(rand(nouns.size))
          result = @words.build_sentence({"first" => seed})
          next if result.nil?
          break
        end
        next if result.nil?
        reply_text = "@" + r[:user][:screen_name] + " " + result
        Twitter.update(reply_text)
        puts reply_text
        replied = r.id
      end
      @log.update({:name => 'replied'}, {'$set' => {:id => replied}})
    end
    
    def tweet(start = "BOS", reverse = false)
      res_text = reverse ? @words.build_sentence_reverse({"third" => start}) : @words.build_sentence({"first" => start})
      Twitter.update(res_text)
      puts res_text
    end
    
    def tweet_gimon
      tweet(/[?？]/, true)
    end
    
    def tweet_ext(query = "山田")
      ext = WordCollection.al_ext_source(query)
      res_text = ext.build_sentence({"first" => "BOS"})
      puts res_text
    end
    
    def test(start = "BOS")
      res_text = @words.build_sentence({"first" => start})
      puts res_text
    end
    
    def collect
      since = @log.find_one({:name => 'since_id'}) || {:name => 'since_id'}
      tl_query = {:count => 200}
      if since_id = since['id']
        tl_query[:since_id] = since_id
      end
      Twitter.home_timeline(tl_query).reverse.each do |tl|
        text = tl[:text]
        # 非公式RTと自分自身は対象外
        next if text.include?("RT @") || tl[:user][:screen_name] == @botconf['screen_name']
        text.gsub!(/http[-_.!~*\'()a-zA-Z0-9;\/?:\@&=+\$,%#]+/, '')
        text.gsub!(/#.+/, "")
        text.gsub!(/@[a-zA-Z0-9_]+/, '')
        TAGGER.parse("BOS" + text + "EOS").force_encoding("UTF-8").split(" ").each_cons(3) do |a|
          @words.save({:first => a[0], :second => a[1], :third => a[2]})
        end
        since_id = tl.id
      end
      if since_id
        since['id'] = since_id
        @log.save(since)
      end
    end
    
    def init
      print "initialize db? [y/N] "
      yn = gets.chomp
      return false if yn.upcase != "Y"
      @words.drop
      @log.drop
      collect
    end
  end
end