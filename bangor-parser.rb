require 'json'
require 'nokogiri'
require 'open-uri'

require './gpc-parser.rb'
require './pronouncer.rb'

module CymraegBot
  class BangorParser
    attr_reader :gpc

    def initialize(gpc)
      @gpc = gpc
    end

    def find
      main_entry ? {
        word: word,
        pronunciations: Pronouncer.new(word).pronunciations,
        plurals: is_noun ? gpc.plurals : [],
        types: types,
        stem: gpc.stem,
        alt: gpc.alt,
        meanings: meanings,
      } : nil
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
      @main_entry ||= data[:entries].lazy.map do |e|
        e[:headword] == word && Nokogiri::HTML(e[:src]).at_css('[property=CSGR_DictionaryEntry]')
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
      @meanings ||= main_entry.css('[property=CSGR_Equivalents][lang=en]').take(2).map {|type| type.css('[property=CSGR_term]').take(4).map(&:text).uniq.join(', ') }.uniq
    end

    def is_noun
      types.any? do |type| type =~ /\bnoun/ end
    end
  end
end
