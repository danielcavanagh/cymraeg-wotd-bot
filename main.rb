# encoding: utf-8
$stdout.sync = true

$version = '0.6.2'
puts 'cymraeg bot ' + $version

require 'cgi'
require 'date'
require 'gmail'
require 'json'
require 'nokogiri'
require 'open-uri'
require 'redd'

require './bangor-parser.rb'
require './gpc-parser.rb'
require './pronouncer.rb'

# FIX word 'us' has no data

type = :continuous
while ARGV.any? and ARGV.first[0] == '-'
  case ARGV.shift
  when '-p' then type = :pronounce
  when '-s' then type = :single
  when '-t' then type = :test
  end
end

given_word = ARGV.first

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
  if type == :continuous
    tomorrow = Date.today.next_day.to_time.utc + Time.now.utc_offset
    offset = tomorrow - Time.now
    puts 'sleeping til midnight (' + offset.to_s + ' secs)'
    sleep offset
  end

  word = nil

  while true
    begin
      word_id =
        if given_word then Nokogiri::XML(URI::open('https://geiriadur.ac.uk/gpc/servlet?func=search&str=' + CGI.escape(given_word)).read).at_css('matchId').text rescue nil
        elsif URI::open('https://geiriadur.ac.uk/gpc/servlet?func=random').read =~ /\d+/ then $~.to_s
        else nil
        end

      if word_id
        doc = Nokogiri::XML(URI::open('https://geiriadur.ac.uk/gpc/servlet?func=entry&id=' + word_id))
        gpc = CymraegBot::GPCParser.new(doc)
        if gpc.word
          puts 'word from gpc: ' + gpc.word unless given_word

          word = CymraegBot::BangorParser.new(gpc).find
          if word and (word[:meanings].length > 1 or word[:meanings].first != gpc.word)
            puts 'word: ' + word[:word]
            puts 'meaning: ' + word[:meanings][0]
            print 'post this word? [Yn] '
            answer = STDIN.gets.strip
            break if answer.downcase == 'y' or answer == ''
            exit if given_word

          elsif given_word
            puts 'no valid definition found in geiriadur bangor'
            exit
          end
        end

      elsif given_word
        puts 'word not found in gpc'
        exit
      end
    rescue
      puts 'error: ' + $!.message + "\n" + $!.backtrace.join("\n")
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

  break if type != :continuous

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
