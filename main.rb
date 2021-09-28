# encoding: utf-8
$stdout.sync = true

$version = '0.6.2'
puts 'cymraeg bot ' + $version

require 'date'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'redd'
require 'gmail'

require './bangor-parser.rb'
require './gpc-parser.rb'
require './pronouncer.rb'

# FIX word 'us' has no data

type = :normal
while ARGV.any? and ARGV.first[0] == '-'
  case ARGV.shift
  when '-p' then type = :pronounce
  when '-s' then type = :single
  when '-t' then type = :test
  end
end

if type == :pronounce
  all_ps = ARGV.map {|word|
    CymraegBot::Pronouncer.new(word).pronunciations
  }
  puts 'north: ' + all_ps.map {|p| p[:north][0] }.join(' ')
  puts 'south: ' + all_ps.map {|p| p[:south][0] }.join(' ')
  exit
end


while true
begin
  if type == :normal
    tomorrow = Date.today.next_day.to_time.utc + Time.now.utc_offset
    offset = tomorrow - Time.now
    puts 'sleeping til midnight (' + offset.to_s + ' secs)'
    sleep offset
  end

  word = nil

  while true
    begin
      word_id =
        if ARGV.any? then Nokogiri::XML(URI::open('http://welsh-dictionary.ac.uk/gpc/servlet?func=search&str=' + ARGV.first).read).at_css('matchId').text rescue nil
        elsif URI::open('http://www.geiriadur.ac.uk/gpc/servlet?func=random').read =~ /\d+/ then $~.to_s
        else nil
        end
      next if not word_id
      doc = Nokogiri::XML(URI::open('http://www.geiriadur.ac.uk/gpc/servlet?func=entry&id=' + word_id))

      gpc = CymraegBot::GPCParser.new(doc)
      if gpc.word
        puts 'word from gpc: ' + gpc.word

        word = CymraegBot::BangorParser.new(gpc).find
        next unless word and (word[:meanings].length > 1 or word[:meanings].first != gpc.word)

        puts 'word: ' + word[:word]
        puts 'meaning: ' + word[:meanings][0]
        print 'post this word? [Yn] '
        answer = STDIN.gets.strip
        break if answer.downcase == 'y' or answer == ''
      end
    rescue
      puts 'error: ' + $!.message + "\n" + $!.backtrace.join("\n")
      next
    end

    if ARGV.any?
      puts 'no word or word has the same definition'
      exit
    end
  end

  recording_url = 'http://forvo.com/word/' + word[:word] + '/#cy'
  recording_html = URI::open(recording_url).read rescue ''
  headword =
    if recording_html.include?('#cy') then '[**' + word[:word].capitalize + '**](' + recording_url + ')'
    else word[:word].capitalize
    end

  pronunciation =
    if word[:pronunciations] then
      if word[:pronunciations][:north][0] == word[:pronunciations][:south][0] then '/' + word[:pronunciations][:north][0] + '/'
      else '/' + word[:pronunciations][:north][0] + '/ (North), /' + word[:pronunciations][:south][0] + '/ (South)'
      end
    else nil
    end

  text = headword + ' - ' + word[:meanings].join('; ') +
         (pronunciation ? "\n\n***Pronunciation***: " + pronunciation : '') +
         (word[:types].any? ? "\n\n***Type***: " + word[:types].join(', ') : '') +
         (word[:plurals].any? ? "\n\n***Plural***: " + word[:plurals].first : '') +
         (word[:alt] ? "\n\n***Alt.***: " + word[:alt] : '') +
         (word[:stem] ? "\n\n***Stem***: " + word[:stem] : '')
  puts text

  if type != :test
    reddit = Redd.it(
      user_agent: 'cymraeg wotd bot ' + $version,
      client_id: ENV['reddit_client_id'],
      secret: ENV['reddit_secret'],
      username: ENV['reddit_username'],
      password: ENV['reddit_password']
    )
    throw 'unable to sign in to reddit' if not reddit

    learnwelsh = reddit.subreddit('learnwelsh')
    throw 'unable to load subreddit' if not learnwelsh

    res = learnwelsh.submit('WWOTD: ' + word[:word].capitalize, text: text, sendreplies: false)
    throw 'unable to submit new word' if not res
  end

  break if type != :normal

rescue
  puts 'error: ' + $!.message + "\n" + $!.backtrace.join("\n")
  Gmail.new(ENV['gmail_username'], ENV['gmail_password']) {|gmail|
    gmail.deliver {
      to ENV['gmail_username']
      subject 'cwotd bot error'
      text_part {
        body err
      }
    }
  } if ENV['gmail_username']
end
end
