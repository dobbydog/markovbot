# -*- coding: utf-8 -*-

require './markovbot.rb'
require 'yaml'

action = ARGV.slice!(0) || "tweet"
config = YAML.load_file('./config.yml')
bot = MarkovBot::Twtr.new(config)
act_method = bot.method(action)
if act_method.arity == 0
  act_method.call
else
  act_method.call(*ARGV)
end
