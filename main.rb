# encoding: UTF-8
$stdout.sync = true

$version = '0.2.0'
puts 'cymraeg wotd bot ' + $version

require 'date'
require 'json'
require 'open-uri'
require 'nokogiri'
require 'redd'

$single_run = false
$test_run = false
while ARGV.any? and ARGV.first[0] == '-'
  case ARGV.shift
  when '-s' then $single_run = true
  when '-t' then $test_run = true
  end
end

def random_word
  begin
    if open('http://www.geiriadur.ac.uk/gpc/servlet?func=random').read =~ /\d+/
      random_word_id = $~.to_s
      puts random_word_id
      doc = Nokogiri::XML(open('http://www.geiriadur.ac.uk/gpc/servlet?func=entry&id=' + random_word_id))
    enD
  rescue
    puts 'error finding word'
    nil
  end
  GPCParse.new(doc).words
end

def pronunciations(word)
  return []
end

class BangorParser
  def init(doc)
    @doc = doc
  end

  def parse
    GPCParser.new(doc).words.map do |word|
      json = open('http://geiriadur.bangor.ac.uk/?#' + word) rescue nil
      data = JSON.parse(json, symbolize_names: true)
      data[:entries].map do |e|
        puts e
        nil
      end.find {|e| e }
    end.find {|w| w }
  end
end

class GPCParser
  def init(doc)
    @doc = doc
  end

  def parse
    if doc.search('.p12c').any? {|elem| elem.text =~ /\b(19|2\d)\d\d\b|2\d(-\d)?g./ }
      return {
        word: headword,
        pronunciations: pronunciations(word),
        alts: alts,
        plurals: plurals,
        types: types,
        meanings: meanings.map {|m| m.text.sub(/(?<!also fig)\.$/, '') },
      }
    else return nil
    end
  end

  def words
    @words = [headword] + alts
  end

  def alts
    @alts ||= welsh_lines[0].text.gsub(/\d+\b|:|,/, '').gsub(/[[:space:]]+/, ' ').gsub(/ \([[:word:]]\)/, '').strip.split.reject { |alt| alt == headword or alt == '' }
  end

  def types
    @types ||= welsh_lines[2].css('h').map do |type|
      case type.text
      when 'a.' then 'adjective'
      when 'eg.' then 'noun (masculine)'
      when 'eb.' then 'noun (feminine)'
      when 'eg.b.' then 'noun (masculine/feminine)'
      when 'e.ll.' then 'noun (plural)'
      when 'ba.', 'bg.', 'bg.a.' then 'verb'
      when 'cys.' then 'conjunction'
      else nil
      end
    end.compact
  end

  def plurals
    welsh_lines[2].text.scan(/ll.(?: (?:\(prin\) )?[[[:word:]]()-]+,?)+/).map do |entry|
      entry.sub('ll. ', '').split(', ')
    end.flatten.map do |pattern|
      if pattern.include?('(prin) ') or pattern.include?('hefyd fel') or pattern.include?('weithiau fel') then nil
      elsif pattern[0] == '-' then headword + pattern[1..-1]
      else pattern
      end
    end.compact
  end

  def headword
    @headword ||= doc.css('head').first.text.sub(/\d+$/, '')
  end

  private

  def welsh_lines
    @welsh_lines ||= doc.css('.p12')
  end

  def meanings
    @meanings ||= doc.css('.p22')
  end
end

while true
  tomorrow = Date.today.next_day.to_time.utc + Time.now.utc_offset
  offset = tomorrow - Time.now
  puts 'sleeping til midnight (' + offset.to_s + ' secs)'
  sleep(offset) if not $test_run and not $single_run

  word = nil

  while true
    if w = random_word
      word = BangorParser.new(w)
      break if word
    end
  end

  text = '[**' + word[:word].capitalize + '**](http://forvo.com/word/' + word[:word] + '/#cy) - ' + word[:meanings].join('; ') +
         (word[:pronunciations].any? ? "\n\n***Pronunciation***: " + word[:pronunciations].join(', ') : '') +
         (word[:types].any? ? "\n\n***Type***: " + word[:types].join(', ') : '') +
         (word[:plurals].any? ? "\n\n***Plurals***: " + word[:plurals].join(', ') : '') +
         (word[:alts].any? ? "\n\n***Alt. spellings***: " + word[:alts].join(', ') : '')
  puts text

  if not $test_run
    reddit = Redd.it(:script, ENV['reddit_client_id'], ENV['reddit_secret'], ENV['reddit_username'], ENV['reddit_password'], user_agent: 'cymraeg wotd bot ' + $version)
    reddit.authorize!
    learnwelsh = reddit.subreddit_from_name('learnwelsh')
    learnwelsh.submit('WWOTD: ' + word[:word].capitalize, text: text, sendreplies: false)
  end

  break if $single_run
end
