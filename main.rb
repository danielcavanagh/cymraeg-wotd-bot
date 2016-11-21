# encoding: utf-8
$stdout.sync = true

$version = '0.4.0'
puts 'cymraeg wotd bot ' + $version

require 'date'
require 'json'
require 'open-uri'
require 'nokogiri'
require 'redd'

module Enumerable
  def scan(initial)
    inject([initial]) {|acc, el| acc << yield(acc.last, el) }.drop(1)
  end
end

$single_run = false
$test_run = false
while ARGV.any? and ARGV.first[0] == '-'
  case ARGV.shift
  when '-s' then $single_run = true
  when '-t' then $test_run = true
  end
end

class Pronounce
  UncoveredConsonant = 'tʃ|dʒ|[bdðfghjklɬmm̥nn̥prr̥sʃtθvx]'
  Consonant = "(#{UncoveredConsonant})"
  Vowel = '[ɑa@eɛ%iɪ!ɨɨ̞#oɔ&uʊ]'

  attr_reader :word

  def initialize(word)
    @word = word
  end

  def pronunciations
    north, south = ipa.zip(approximations)
    { north: north, south: south }
  end

  def approximations
    ['', '']
  end

  def ipa
    north_long_i = stress_i == syllables.length - 1 ? stress_i : nil
    north_syllables = long_syllables(stressed_syllables, north_long_i).map do |syll|
      syll.sub(/(?<=#{Vowel})(?=(ɬ|s)#{Consonant})/, 'ː') # long vowels before consonant clusters beginning ll and s
    end
    north_ipa = deprotect_vowels(north_syllables.join)
                .gsub('l', 'ɫ')

    # XXX 'tyst' is wrong for south
    south_syllables = long_syllables(stressed_syllables, stress_i).each_with_index.map do |syll, i|
      if i == syllables.length - 2 then syll.sub(/(?<=#{Vowel})ː(?=ɬ#{Consonant})/, '') # short vowels in the penult before ll
      else syll
      end
    end
    south_ipa = deprotect_vowels(south_syllables.join)
      .gsub('ɨ̞', 'ɪ')
      .gsub('ɨ', 'i')
      .gsub('ɑːi', 'ai')

    # TODO irregular stress
    # TODO epenthetic echo vowel, eg. cenedl -> 'kenedel

    [north_ipa, south_ipa]
  end

  def syllables
    @syllables ||=
      base_ipa.to_enum(:scan, /^#{Consonant}*|(?<=#{UncoveredConsonant})?#{Consonant}+?#{Vowel}/).map { Regexp.last_match.begin(0) } # find starting index of each syllable
      .reverse.scan(base_ipa.length..0) { |prev, pos| pos...prev.first }.reverse # map the indices to ranges
      .map { |range| base_ipa[range] } # map indices to substrings (ie. syllables)
  end

  def base_ipa
    @base_ipa ||= word \
      .gsub(/[^[[:word:]]]/, '') \
      # protect vowels from conflict with ipa vowels
      .gsub('a', '@')
      .gsub('e', '%')
      .gsub('i', '!')
      .gsub('o', '&')
      .gsub('u', '#') \
      # consonants
      .gsub(/c(?!h)/, 'k')
      .gsub('dd', 'ð')
      .gsub(/ff|ph/, 'f')
      .gsub('j', 'dʒ')
      .gsub('ll', 'ɬ')
      .gsub('mh', 'm̥')
      .gsub('nh', 'n̥')
      .gsub('ngh', 'ŋ̊')
      .gsub('rh', 'r̥')
      .gsub(/s!(?=#{Vowel})|sh|(?<=t)ch$/, 'ʃ')
      .gsub('th', 'θ')
      .gsub('ch', 'x')
      .gsub(/(?<!f)f/, 'v')
      .gsub(/!(?=#{Vowel})/, 'j') \
      # w glides
      .gsub(/(?<=g)w(?=r|n)/, 'ʷ')
      .gsub(/(?<=ch)w/, 'ʷ') \
      # long Vowels
      .gsub('â', 'ɑː')
      .gsub('ê', 'eː')
      .gsub('î', 'iː')
      .gsub('ô', 'oː')
      .gsub(/û|ŷ/, 'ɨː')
      .gsub('ŵ', 'uː') \
      # short Vowels
      .gsub('à', 'a')
      .gsub('è', 'ɛ')
      .gsub('ì', 'ɪ')
      .gsub('ò', 'ɔ')
      .gsub(/ù|ỳ/, 'ɨ̞')
      .gsub('ẁ', 'ʊ') \
      # diphthongs
      .gsub(/@#|á#/, 'aɨ')
      .gsub('@w', 'au')
      .gsub('@%', 'ɑːɨ')
      .gsub('%!', 'əi')
      .gsub('%#', 'əɨ')
      .gsub('%w', 'ɛu')
      .gsub('!w', 'ɪu')
      .gsub(/#w|yw/, 'ɨu') # XXX does yw sound like this in all syllables, or just the final syllable?
      .gsub('&!', 'ɔi')
      .gsub('&%', 'ɔɨ')
      .gsub(/(?<!#{Vowel})wy/, 'ʊɨ') \
      # TODO also /uːɨ/ in north
      .gsub('y', 'ə') # lucky last. undo this in the final syllable later on
  end

  def stress_i
    @stress_i ||= syllables.length == 1 ? 0 : syllables.length - 2
  end

  def stressed_syllables
    # TODO acute accent (´) is sometimes used to mark a stressed final syllable in a polysyllabic word.
    @stressed_syllables ||= syllables.each_with_index.map do |syll, i|
      stressed = i == stress_i ? 'ˈ' + syll : syll
      if i == syllables.length - 1 and stressed =~ /#{Consonant}ə#{Consonant}#{syllables.length == 1 ? '+' : ''}$/ then stressed.sub('ə', '#')
      else stressed
      end
    end
  end

  def long_syllables(syllables, long_index)
    syllables.each_with_index.map do |syll, i|
      if i == long_index then long_syllable(syll, syllables[i + 1])
      else syll
      end
    end
  end

  def long_syllable(syllable, next_syll)
    if next_syll.nil? then
      if syllable !~ /#{Consonant}/
        syllable # this should only match single-vowel words
      else
        syllable
          .sub(/(?<!#{Vowel})(?<=#{Vowel})(?=[bdðfgθvx]$)/, 'ː') # preceeding certain consonants
          .sub(/(?<=#{Vowel})(?=s?$)/, 'ː') # word-final s or word-final vowel
      end
    else
      if syllable =~ /#{Vowel}$/ and next_syll =~ /^[bdðfgθvx]/ then syllable + 'ː' # preceeding certain consonants
      else syllable
      end
    end
  end

  def deprotect_vowels(word)
    word
      .gsub('@ː', 'ɑː')
      .gsub('@', 'a')
      .gsub('%ː', 'eː')
      .gsub('%', 'ɛ')
      .gsub('!ː', 'iː')
      .gsub('!', 'ɪ')
      .gsub('&ː', 'oː')
      .gsub('&', 'ɔ')
      .gsub('#ː', 'ɨː')
      .gsub('#', 'ɨ̞')
  end
end

p = Pronounce.new(ARGV.first).pronunciations
puts p[:north][0], p[:south][0]
exit

class BangorParser
  attr_reader :gpc

  def initialize(gpc)
    @gpc = gpc
  end

  def find
    {
      word: word,
      pronunciations: Pronounce.new(word).pronunciations,
      plurals: is_noun ? gpc.plurals : [],
      types: types,
      stem: gpc.stem,
      alt: gpc.alt,
      meanings: entry.css('[property=CSGR_Equivalents][lang=en]').take(2).map {|type| type.css('[property=CSGR_term]').take(4).map(&:text).join(', ') }
    }
  end

  def word
    @word ||= gpc.word
  end

  def data
    return @data if @data
    json = open('http://api-dev.termau.cymru/Cysgair/Search/Default.ashx?apikey=C353DE38D8DB4BD6ABD1C78109871EF8&format=json&string=' + word).read rescue nil
    @data = JSON.parse(json, symbolize_names: true) rescue { entries: [] }
  end

  def main_entry
    @entry ||= data[:entries].lazy.map do |e|
      Nokogiri::HTML(e[:src]).at_css('[property=CSGR_DictionaryEntry]')
    end.find {|e| e }
  end

  def types
    @types ||= main_entry.css('[property=CSGR_ptOfSpeech]').map(&:text).map do |abbr|
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

  def meanings
     @meanings ||= main_entry.css('[property=CSGR_Equivalents][lang=en]').take(2).map {|type| type.css('[property=CSGR_term]').take(4).map(&:text).join(', ') }
  end

  def is_noun
    types.any? do |type| type =~ /\bnoun/ end
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
        pronunciations: Pronounce.new(word).pronunciations,
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
