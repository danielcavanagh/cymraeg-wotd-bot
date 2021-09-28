require 'cgi'
require 'json'
require 'net/http'
require 'nokogiri'
require 'uri'

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
      json = Net::HTTP.get(URI('http://api.termau.org/Cysgair/Search/Default.ashx?apikey=701658f94A23486B941D64B70C7BC03C&format=json&dln=cy&string=' + CGI.escape(word)), { Referer: 'http://termau.cymru/' })
      @data = JSON.parse(json, symbolize_names: true) rescue Hash.new
      @data = ({ entries: [] }).merge(@data)
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
