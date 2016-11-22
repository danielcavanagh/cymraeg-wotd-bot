# encoding: utf-8
$stdout.sync = true

$version = '0.4.0'
puts 'cymraeg bot ' + $version

require 'date'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'redd'

require './bangor-parser.rb'
require './gpc-parser.rb'

$single_run = false
$test_run = false
while ARGV.any? and ARGV.first[0] == '-'
  case ARGV.shift
  when '-s' then $single_run = true
  when '-t' then $test_run = true
  end
end

while true
  tomorrow = Date.today.next_day.to_time.utc + Time.now.utc_offset
  offset = tomorrow - Time.now
  puts 'sleeping til midnight (' + offset.to_s + ' secs)'
  sleep(offset) if not $test_run and not $single_run

  word = nil

  while true
    begin
      word_id =
        if ARGV.any? then ARGV.shift
        elsif open('http://www.geiriadur.ac.uk/gpc/servlet?func=random').read =~ /\d+/ then $~.to_s
        else nil
        end
      doc = Nokogiri::XML(open('http://www.geiriadur.ac.uk/gpc/servlet?func=entry&id=' + word_id))
    rescue
      next
    end

    gpc = CymraegBot::GPCParser.new(doc)
    if gpc.word
      word = CymraegBot::BangorParser.new(gpc).find
      break if word
    end
  end

  recording_url = 'http://forvo.com/word/' + word[:word] + '/#cy'
  recording_html = open(recording_url).read rescue ''
  headword =
    if recording_html.include?('#cy') then '[**' + word[:word].capitalize + '**](' + recording_url + ')'
    else word[:word].capitalize
    end

  text = headword + ' - ' + word[:meanings].join('; ') +
         (word[:pronunciations] ? "\n\n***Pronunciation***: /" + word[:pronunciations][:north][0] + '/ (North), /' + word[:pronunciations][:south][0] + '/ (South)' : '') +
         (word[:types].any? ? "\n\n***Type***: " + word[:types].join(', ') : '') +
         (word[:plurals].any? ? "\n\n***Plural***: " + word[:plurals].first : '') +
         (word[:alt] ? "\n\n***Alt.***: " + word[:alt] : '') +
         (word[:stem] ? "\n\n***Stem***: " + word[:stem] : '')
  puts text

  if not $test_run
    reddit = Redd.it(:script, ENV['reddit_client_id'], ENV['reddit_secret'], ENV['reddit_username'], ENV['reddit_password'], user_agent: 'cymraeg wotd bot ' + $version)
    reddit.authorize!
    learnwelsh = reddit.subreddit_from_name('learnwelsh')
    learnwelsh.submit('WWOTD: ' + word[:word].capitalize, text: text, sendreplies: false)
  end

  break if $single_run
end
