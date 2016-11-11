# encoding: UTF-8

require 'date'
require 'open-uri'
require 'nokogiri'
require 'redd'

def make_alts(word, line)
  line.text.gsub(/\d+\b|:|,/, '').gsub(/[[:space:]]+/, ' ').gsub(/ \(\w\)/, '').strip.split.reject { |alt| alt == word }
end

def make_types(line)
  line.css('h').map do |type|
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

def make_plurals(word, line)
  puts line.text
  line.text.scan(/ll.(?: (?:\(prin\) )?[\w()-]+,?)+/).map do |entry|
    entry.sub('ll. ', '').split(', ')
  end.flatten.map do |pattern|
    if pattern.include?('(prin) ') or pattern.include?('hefyd fel') or pattern.include?('weithiau fel') then nil
    elsif pattern[0] == '-' then word + pattern[1..-1]
    else pattern
    end
  end.compact
end

while true
  tomorrow = Date.today.next_day.to_time.utc + Time.now.utc_offset
  offset = tomorrow - Time.now
  puts 'sleeping til midnight (' + offset.to_s + ' secs)'
  sleep(offset)

  word = nil

  while true
    if open('http://www.geiriadur.ac.uk/gpc/servlet?func=random').read =~ /\d+/
      random_word_id = $~.to_s
      doc = Nokogiri::XML(open('http://www.geiriadur.ac.uk/gpc/servlet?func=entry&id=' + random_word_id))
      if doc.search('.p12c').any? {|elem| elem.text =~ /\b(19|2\d)\d\d\b|2\d(-\d)?g./ }
        unit = {
          headword: doc.css('head').first.text.sub(/\d+$/, ''),
          welsh_lines: doc.css('.p12'),
          meanings: doc.css('.p22'),
        }

        word = {
          word: unit[:headword],
          alts: make_alts(unit[:headword], unit[:welsh_lines][0]),
          plurals: make_plurals(unit[:headword], unit[:welsh_lines][2]),
          types: make_types(unit[:welsh_lines][2]),
          meanings: unit[:meanings].map {|m| m.text },
        }
      end
    end
  end

  reddit = Redd.it(:script, ENV['reddit_client_id'], ENV['reddit_secret'], ENV['reddit_username'], ENV['reddit_password'], user_agent: 'cymraeg wotd bot 0.1.0')
  reddit.authorize!
  learnwelsh = reddit.subreddit_from_name('learnwelsh')
  learnwelsh.submit(
    'WWOTD: ' + word[:word],
    text: word[:word] + ' - ' + word[:meanings].join(' ') + "\n\n" +
          'pronunciation: ' + 'TODO' + "\n" +
          'type: ' + word[:meanings].join(' ') + "\n" +
          'plurals: ' + word[:plurals].join(', ') + "\n" +
          'alt spellings: ' + word[:alts].join(', '),
    sendreplies: false)
end
