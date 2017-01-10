# encoding: utf-8

module CymraegBot
  module Refinements
    refine Array do
      def scan(initial)
        inject([initial]) {|acc, el| acc << yield(acc.last, el) }.drop(1)
      end
    end
  end

  class Pronouncer
    using Refinements

    UncoveredConsonant = 'tʃ|dʒ|[bdðfghjklɫɬmm̥nn̥prr̥sʃtθvwχ]'
    Consonant = "(#{UncoveredConsonant})"
    Vowel = '[ɑa@eɛ%iɪ!ɨɨ̞#oɔ&uʊ=yə]'
    LongableVowel = '[@%!#&]'

    attr_reader :word

    def initialize(word)
      @word = word.downcase
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
        syll.sub(/(?<=#{Vowel})(?=(ɬ|s)#{Consonant})/, 'ː') # long vowels before consonant clusters beginning with ll and s
      end
      north_ipa = deprotect_vowels(north_syllables.join)

      #south_syllables = long_syllables(stressed_syllables, stress_i).each_with_index.map do |syll, i|
      south_syllables = long_syllables(stressed_syllables, north_long_i).each_with_index.map do |syll, i|
        if i == syllables.length - 2 then syll.sub(/(?<=#{Vowel})ː(?=ɬ#{Consonant})/, '') # short vowels in the penult before ll
        else syll
        end
      end
      south_ipa = deprotect_vowels(south_syllables.join)
        .gsub('ɨ̞', 'ɪ') # u -> i
        .gsub('ɨ', 'i') # u -> i
        .gsub(/(?<=#{UncoveredConsonant}|#{Vowel}{2})ɪ$/, 'i') # word-final ɪ is raised
        .gsub('ɑːi', 'ai')

      # TODO acute accent
      # TODO irregular stress
      # TODO epenthetic echo vowel, eg. cenedl -> 'kenedel

      [north_ipa, south_ipa]
    end

    def syllables
      @syllables ||=
        base_ipa.to_enum(:scan, /^#{Consonant}*|(?<!#{UncoveredConsonant})#{Consonant}(?=#{Vowel})|(?<=#{UncoveredConsonant})#{Consonant}+(?=#{Vowel})|(?<=#{Vowel}{2})#{Vowel}/).map { Regexp.last_match.begin(0) } # find starting index of each syllable
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
        .gsub('j', 'dʒ')
        .gsub('ll', 'ɬ')
        .gsub('mh', 'm̥')
        .gsub(/n+/, 'n')
        .gsub('nh', 'n̥')
        .gsub('ngh', 'ŋ̊')
        .gsub('rh', 'r̥')
        .gsub(/s!(?=#{Vowel})|sh|(?<=t)ch$/, 'ʃ')
        .gsub('th', 'θ')
        .gsub('ch', 'χ')
        .gsub(/(?<!f)f(?!f)/, 'v')
        .gsub(/ff|ph/, 'f')
        .gsub(/(?<=^|#{UncoveredConsonant})!(?=#{Vowel}|w(?!#{Vowel}))/, 'j') \
        # clusters
        .gsub('st', 'sd') \
        # w
        .gsub(/(?<=g)w(?=r|n)/, 'ʷ')
        .gsub(/(?<=χ)w/, 'ʷ')
        .gsub(/(?<=#{UncoveredConsonant}|#{Vowel}{2})w(?=#{UncoveredConsonant})/, '=') \
        # long vowels
        .gsub('â', 'ɑː')
        .gsub('ê', 'eː')
        .gsub('î', 'iː')
        .gsub('ô', 'oː')
        .gsub(/û|ŷ/, 'ɨː')
        .gsub('ŵ', 'uː') \
        # short vowels
        .gsub('à', 'a')
        .gsub('è', 'ɛ')
        .gsub('ì', 'ɪ')
        .gsub('ò', 'ɔ')
        .gsub(/ù|ỳ/, 'ɨ̞')
        .gsub('ẁ', 'ʊ') \
        # diphthongs TODO how many of these are needed
        .gsub(/@#|á#/, 'aɨ')
        .gsub('@w', 'au') # TODO also long a in north
        .gsub('@%', 'ɑːɨ')
        .gsub('%!', 'ei')
        .gsub('%#', 'eɨ')
        .gsub('%w', 'ɛu') # TODO also long e in north
        .gsub(/!w(?=#{UncoveredConsonant})/, 'ɪu')
        .gsub(/(#w|yw)(?=#{UncoveredConsonant})/, 'ɨu') # TODO also əu for yw sometimes
        .gsub('&!', 'ɔi')
        .gsub('&#', 'ɔɨ') # TODO also long o in north
        .gsub('&%', 'ɔɨ') # TODO also long o in north
        .gsub(/(?<!#{Vowel})wy/, 'ʊɨ') # TODO also long w in north. sometimes w is w, not u, depending on preceeding consonant?
        .gsub('y', 'ə') # lucky last. undo this in the final syllable later on
    end

    def stress_i
      @stress_i ||= syllables.length == 1 ? 0 : syllables.length - 2
    end

    def stressed_syllables
      # TODO acute accent (´) is sometimes used to mark a stressed final syllable in a polysyllabic word.
      @stressed_syllables ||= syllables.each_with_index.map do |syll, i|
        stressed = i == stress_i ? 'ˈ' + syll : syll
        if i == syllables.length - 1 then stressed.sub(/(?<=#{UncoveredConsonant})ə(?=#{UncoveredConsonant})#{syllables.length > 1 ? '?' : ''}/, '#')
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
      if next_syll.nil?
        if syllable !~ /#{Consonant}/ then syllable # this should only match single-vowel words
        else
          syllable
            .sub(/(?<!#{Vowel})(?<=#{LongableVowel})(?=[bdðfgθvχ]$)/, 'ː') # preceeding certain consonants
            .sub(/(?<=#{LongableVowel})(?=s?$)/, 'ː') # word-final s or word-final vowel
        end
      elsif syllable =~ /#{LongableVowel}$/ and next_syll =~ /^[bdðfgθvχ]/ then syllable + 'ː' # preceeding certain consonants
      else syllable
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
        .gsub('=ː', 'uː')
        .gsub('=', 'ʊ')
    end
  end
end
