# encoding: UTF-8
$stdout.sync = true

$version = '0.3.0'
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

def pronunciations(word)
  return []
end

class BangorParser
  attr_reader :gpc

  def initialize(gpc)
    @gpc = gpc
  end

  def find
    word = gpc.word
    json = open('http://api-dev.termau.cymru/Cysgair/Search/Default.ashx?apikey=C353DE38D8DB4BD6ABD1C78109871EF8&format=json&string=' + word).read rescue nil
    data = JSON.parse(json, symbolize_names: true) rescue { entries: [] }
    data[:entries].lazy.map do |e|
      entry = Nokogiri::HTML(e[:src]).at_css('[property=CSGR_DictionaryEntry]')
      {
        word: word,
        pronunciations: pronunciations(word),
        plurals: gpc.plurals,
        types: types(entry.css('[property=CSGR_ptOfSpeech]').map(&:text)),
        stem: gpc.stem,
        alt: gpc.alt,
        meanings: entry.css('[property=CSGR_Equivalents][lang=en]').take(2).map {|type| type.css('[property=CSGR_term]').take(4).map(&:text).join(', ') }
      }
    end.find {|e| e }
  end

  def types(abbrs)
    abbrs.map do |abbr|
      case abbr
      when 'adf' then 'adverb'
      when 'ans' then 'adjective'
      when 'eb' then 'noun (feminine)'
      when 'eg' then 'noun (masculine)'
      when 'eg/b', 'eb/g' then 'noun (masculine/feminine)'
      when 'ell' then 'noun (plural)'
      when 'be' then 'verbnoun'
      else nil
      end
    end.compact
  end
end

class GPCParser
  attr_reader :doc

  def initialize(doc)
    @doc = doc
  end

  def parse
    if doc.search('.p12c').any? {|elem| elem.text =~ /\b(19|2\d)\d\d\b|2\d(-\d)?g./ }
      return {
        word: word,
        pronunciations: pronunciations(word),
        plurals: plurals,
        stem: stem,
        types: types,
        alt: alt,
        meanings: meanings,
      }
    else return nil
    end
  end

  def alt
    @alt ||= is_number? ? feminine_number : nil
  end

  def types
    @types ||= welsh_lines[2].css('h').map do |type|
      case type.text
      when 'a.' then 'adjective'
      when 'eg.', 'rhif.' then 'noun (masculine)'
      when 'eb.' then 'noun (feminine)'
      when 'eg.b.' then 'noun (masculine/feminine)'
      when 'e.ll.' then 'noun (plural)'
      when 'ba.', 'bg.', 'bg.a.' then 'verbnoun'
      when 'cys.' then 'conjunction'
      else nil
      end
    end.compact
  end

  def feminine_number
    @feminine_number ||= welsh_lines[2].text.match(/b. ([[:word:]]+)/)[1] + ' (feminine)'
  end

  def plurals
    return @plurals if @plurals
    return @plurals = [] if is_number?

    @plurals =
      welsh_lines[2].text.scan(/ll.(?: (?:\(prin\) )?[[[:word:]]()-]+,?)+/).map do |entry|
        entry.sub('ll. ', '').split(', ')
      end.flatten.map do |pattern|
        if pattern.include?('(prin) ') or pattern.include?('hefyd fel') or pattern.include?('weithiau fel') then nil
        elsif pattern[0] == '-' then headword + pattern[1..-1]
        else pattern
        end
      end.compact
  end

  def stem
    if is_verb? then headword.sub(/af$/, '') + '-'
    else nil
    end
  end

  def headword
    @headword ||= doc.css('head').first.text.sub(/\d+$/, '')
  end

  def word
    @word ||=
      if is_verb? && welsh_lines[0].text.include?(':') then welsh_lines[0].text.match(/:\s+([[[:word:]]()-]+)/)[1]
      else headword
      end
  end

  def meanings
    @meanings ||= doc.css('.p22').map {|m| m.text.sub(/(?<!also fig)\.$/, '') }
  end

  def is_number?
    @is_number ||= welsh_lines[2].text.include?('rhif.')
  end

  def is_verb?
    @is_verb ||= types.first.include?('verb')
  end

  private

  def welsh_lines
    @welsh_lines ||= doc.css('.p12')
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

    gpc = GPCParser.new(doc)
    if gpc.word
      word = BangorParser.new(gpc).find
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
         (word[:pronunciations].any? ? "\n\n***Pronunciation***: " + word[:pronunciations].join(', ') : '') +
         (word[:types].any? ? "\n\n***Type***: " + word[:types].join(', ') : '') +
         (word[:plurals].any? ? "\n\n***Plurals***: " + word[:plurals].join(', ') : '') +
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
