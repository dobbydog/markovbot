#!/usr/bin/ruby --
# -*- coding: utf-8 -*-

require '/path/to/markovbot.rb'
require 'cgi'
require 'json'

cgi = CGI.new
sentences = JSON.parse(cgi['sentences'])
al = MarkovBot::WordCollection::make_al_from_array(sentences)
res_text = al.build_sentence({'first' => 'BOS'})
#print "Access-Control-Allow-Origin: *\n"
print "Content-Type: text/plain\n\n"
puts res_text
