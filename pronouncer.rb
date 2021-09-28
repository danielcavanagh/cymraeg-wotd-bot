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

    Consonant = 'tʃ|dʒ|[ɡχ]ʷ|[bdðfɡhjklɬmm̥nŋn̥prr̥sʃtθvwχ]'
    Vowel = "[ɑa@eɛ%iɪ!ɨɨ\u031e#oɔ&uʊ=yə]"
    NonSyllabicVowel = "[a\u032fe\u032fi\u032fɨ\u032fo\u032fu\u032f]"
    LongVowel = "[ɑa@eɛ%iɪ!ɨɨ\u031e#oɔ&uʊ=yə]ː"
    LongableVowel = '[@%!#&=y]'
    #LongableVowel = '[@%!#&=]'

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

    # if the prounciation can't be predicted (ie. is exceptional) then just stick it here
    def exception
      case word
      when 'y' then ['ˈə'] * 2
      when 'yr' then ['ˈər'] * 2
      when 'til' then ['ˈtɪl'] * 2
      else nil
      end
    end

    def ipa
      return exception if exception

      north_long_i = stress_i == syllables.length - 1 ? stress_i : nil
      north_syllables = long_syllables(north_adj_sylls(adjusted_syllables), north_long_i)
      north_ipa = deprotect_vowels(north_syllables.join)

      #south_syllables = long_syllables(adjusted_syllables, stress_i).each_with_index.map do |syll, i|
      south_syllables = long_syllables(adjusted_syllables, north_long_i).each_with_index.map do |syll, i|
        if i == syllables.length - 2 then syll.sub(/(?<=#{Vowel})ː(?=ɬ(#{Consonant}))/, '') # short vowels in the penult before ll
        else syll
        end
      end
      south_ipa = deprotect_vowels(south_syllables.join)
        .gsub('ɨ̞', 'ɪ') # u -> i
        .gsub('ɨ', 'i') # u -> i
        .gsub('ɨ̯', 'i̯') # u -> i
        .gsub(/(?<=#{Consonant}|(#{Vowel}){2})ɪ$/, 'i') # word-final ɪ is raised

      # TODO acute accent (´) is sometimes used to mark a stressed final syllable in a polysyllabic word.
      # TODO irregular stress

      [north_ipa, south_ipa]
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
        .gsub('g', 'ɡ')
        .gsub('j', 'dʒ')
        .gsub('ll', 'ɬ')
        .gsub(/^mh/, 'm̥')
        .gsub(/^nh/, 'n̥')
        .gsub(/n+/, 'n')
        .gsub(/^nɡh/, 'ŋ̊')
        .gsub(/nɡ/, 'ŋ')
        .gsub('rh', 'r̥')
        .gsub(/s!(?=#{Vowel})|sh|(?<=t)ch$/, 'ʃ')
        .gsub('th', 'θ')
        .gsub('ch', 'χ')
        .gsub(/(?<!f)f(?!f)/, 'v')
        .gsub(/ff|ph/, 'f')
        .gsub(/(?<=^|#{Consonant})!(?=(#{Vowel})|w(?=#{Consonant}))/, 'j') \
        # clusters
        .gsub('st', 'sd') \
        # w
        .gsub(/(?<=ɡ)w(?=(l|n|r)(#{Vowel}))/, 'ʷ')
        .gsub(/(?<=χ)w/, 'ʷ')
        .gsub(/(?<!^)w(?=#{Consonant}|$)/, '=')
        .gsub(/(?<=ɡw)y/, '#')
        .gsub(/(?<!#{Vowel})w(?=y)/, '=') \
        # long vowels
        .gsub('â', 'ɑː')
        .gsub('ê', 'eː')
        .gsub('î', 'iː')
        .gsub('ô', 'oː')
        .gsub(/û|ŷ/, 'ɨː')
        .gsub('ŵ', 'uː') \
        # TODO this works for amlïaws but does it work for anything else? are these letters even possible?
        .gsub('ä', 'ɑː')
        .gsub('ë', 'eː')
        .gsub('ï', 'iː')
        .gsub('ö', 'oː')
        .gsub(/ü|ÿ/, 'ɨː')
        .gsub('ẅ', 'uː') \
        # short vowels
        .gsub('à', 'a')
        .gsub('è', 'ɛ')
        .gsub('ì', 'ɪ')
        .gsub('ò', 'ɔ')
        .gsub(/ù|ỳ/, 'ɨ̞')
        .gsub('ẁ', 'ʊ') \
        # diphthongs
        .gsub(/(?<=#{Vowel})!/, 'i̯')
        .gsub(/(?<=#{Vowel})#/, 'ɨ̯')
        .gsub(/(?<=#{Vowel})%/, 'e̯')
        .gsub(/(?<=#{Vowel})y/, 'ɨ̯')
        .gsub(/(?<=#{Vowel})=/, 'u̯') \
        # disyllabic vowels
        .gsub('á', '@')
        .gsub('é', '%')
        .gsub('í', '!')
        .gsub('ó', '&')
        .gsub('ú', '#')
    end

    def syllables
      @syllables ||=
        base_ipa.to_enum(:scan, /^(#{Consonant})*|(?<!#{Consonant})(#{Consonant})(?=#{Vowel})|(?<=#{Consonant})(#{Consonant})+(?=#{Vowel})|(?<=#{Vowel}|#{LongVowel}|#{NonSyllabicVowel})#{Vowel}(?!\u032f)|(?<=#)#{LongableVowel}/).map { Regexp.last_match.begin(0) } # find starting index of each syllable
        .reverse.scan(base_ipa.length..0) { |prev, pos| pos...prev.first }.reverse # map the indices to ranges
        .map { |range| base_ipa[range] } # map indices to substrings (ie. syllables)
    end

    def stress_i
      @stress_i ||= syllables.length == 1 ? 0 : syllables.length - 2
    end

    # alters diphthongs depending on their syllable, lengthens 'y' in final syllable, and marks stressed syllable
    def adjusted_syllables
      @adjusted_ayllables ||= syllables.each_with_index.map do |syll, i|
        stressed = i == stress_i ? 'ˈ' + syll : syll

        # alter diphthongs in monosyllabic words / final syllables where relevant
        # yw - final syllable -> ɨ̞u̯ (then u -> i for south)
        # ae - nonfinal syllable -> eɨ̯ (then u -> i for south)
        diph_adjusted =
          if not syllables[i + 1].nil? and stressed.include?('@e̯') then stressed.sub('@e̯', 'ee̯')
          else stressed
          end

        #if i == syllables.length - 1 then stressed.sub(/(?<=#{Consonant})y(?=#{Consonant})#{syllables.length > 1 ? '?' : ''}/, '#')
        if i == syllables.length - 1 then diph_adjusted.sub(/y/, '#')
        else diph_adjusted
        end
      end
    end

    def north_adj_sylls(syllables)
      syllables.each_with_index.map do |syll, i|
        lengthened = syll.sub(/(?<=#{Vowel})(?=(ɬ|s)(#{Consonant}))/, 'ː') # long vowels before consonant clusters beginning with ll and s

        # alter diphthongs in monosyllabic words / final syllables where relevant
        # ae - final syllable ->  aːɨ̯
        # oe - monosyllabic word -> oːɨ̯
        # wy - monosyllabic word -> uːɨ̯
        # aw - open monosyllabic word -> aːu̯
        # ew - open monosyllabic word -> eːu̯
        if not syllables[i + 1].nil? then lengthened
        else
          if lengthened.include?('@e̯') then lengthened.sub('@e̯', 'ɑːɨ̯')
          elsif i == 0
            if lengthened =~ /@u̯$/ then lengthened.sub('@u̯', 'ɑːu̯')
            elsif lengthened =~ /%u̯$/ then lengthened.sub('%u̯', 'eːu̯')
            elsif lengthened.include?('&e̯') then lengthened.sub('&e̯', 'oːe̯')
            elsif lengthened.include?('=ɨ̯') then lengthened.sub('=ɨ̯', 'uːɨ̯')
            else lengthened
            end
          else lengthened
          end
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
        if syllable !~ /(#{Consonant})/ then syllable # this should only match single-vowel words
        else
          syllable
            .sub(/(?<!#{Vowel})(#{LongableVowel})(?=[bχdðfɡθv]$)/, '\1ː') # preceeding certain consonants
            .sub(/(?<!#{Vowel})([!#])(?=[lnr]$)/, '\1ː') # preceeding certain consonants
            .sub(/(#{LongableVowel})(?=s?$)/, '\1ː') # long vowel before word-final s or when open
        end
      elsif syllable =~ /#{LongableVowel}$/ and next_syll =~ /^[bχdðfɡsθv]/ then syllable + 'ː' # preceeding certain consonants
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
        .gsub('yː', 'ɨː')
        .gsub('y', 'ə')
        .gsub('e̯', 'ɨ̯')
    end
  end
end
