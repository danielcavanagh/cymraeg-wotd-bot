require 'nokogiri'
require 'open-uri'

require './pronouncer.rb'

module CymraegBot
  class GPCParser
    attr_reader :doc

    def initialize(word)
      @doc =
        if word.is_a? Nokogiri::XML::Document then word
        else doc = Nokogiri::XML(URI::open('http://www.geiriadur.ac.uk/gpc/servlet?func=entry&id=' + word.to_s))
        end
    end

    def parse
      if doc.search('.p12c').any? {|elem| elem.text =~ /\b(19|2\d)\d\d\b|2\d(-\d)?g./ }
        return {
          word: word,
          pronunciations: Pronouncer.new(word).pronunciations,
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
      @alt ||= welsh_lines[2]&.text =~ /\(b\./ ? feminine_alt : nil
    end

    def types
      @types ||= (welsh_lines[2].css('h').map do |type|
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
      end.compact rescue [])
    end

    def feminine_alt
      @feminine_alt ||= welsh_lines.length >= 3 ? welsh_lines[2].text.match(/\(b. ([[:word:]]+)/)[1] + ' (feminine)' : nil
    end

    def plurals
      return @plurals if @plurals
      return @plurals = [] if is_number? or welsh_lines.length < 3

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
      @is_number ||= welsh_lines[2]&.text.include?('rhif.')
    end

    def is_verb?
      @is_verb ||= types.any? && types.first.include?('verb')
    end

    private

    def welsh_lines
      @welsh_lines ||= doc.css('.p12')
    end
  end
end
