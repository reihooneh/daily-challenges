# frozen_string_literal: true

require_relative 'spoken'

module Lungful
  class InputError < StandardError; end

  # A script to be read aloud, split into sections, paragraphs and phrases.
  #
  #   # Introduction [1:00]          a section, with an optional target time
  #   Hi, I'm Sam. [ON SCREEN: logo] text in [square brackets] is a direction, not spoken
  #   (pause)                        an explicit pause
  module Script
    MAX_BYTES = 64 * 1024
    MAX_LINE = 2000
    MAX_SECTIONS = 50
    MAX_WORDS = 12_000

    HEADING = /\A\#{1,3}[ \t]+(.+?)(?:[ \t]*\[(\d{1,2}):([0-5]\d)\])?[ \t]*\z/
    # Control characters and the invisible characters that reorder text on screen.
    FORBIDDEN = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F​-‏‪-‮⁦-⁩﻿]/

    Word = Struct.new(:text, :syllables)
    # A stretch of speech between natural pauses. `pause` is the pause after it, in seconds.
    Phrase = Struct.new(:words, :pause) do
      def syllables = words.sum(&:syllables)
    end
    Section = Struct.new(:title, :target, :paragraphs)

    PAUSES = { ',' => 0.3, ';' => 0.4, ':' => 0.4, '.' => 0.6, '?' => 0.6, '!' => 0.6 }.freeze
    DASHES = ['-', '–', '—'].freeze

    module_function

    def parse(text)
      raise InputError, 'the script is not valid UTF-8 text' unless text.valid_encoding?
      raise InputError, "the script is larger than #{MAX_BYTES / 1024} KB" if text.bytesize > MAX_BYTES

      sections = []
      current = nil # text before the first heading goes into an 'Opening' section
      words = 0
      text.split("\n", -1).each_with_index do |raw, i|
        n = i + 1
        line = raw.chomp("\r")
        raise InputError, "line #{n}: the line is longer than #{MAX_LINE} characters" if line.length > MAX_LINE
        raise InputError, "line #{n}: control or invisible formatting characters are not allowed" if line.match?(FORBIDDEN)

        if (m = HEADING.match(line))
          sections << current if current
          raise InputError, "line #{n}: too many sections (the limit is #{MAX_SECTIONS})" if sections.length >= MAX_SECTIONS

          title = m[1].strip
          raise InputError, "line #{n}: the section title is longer than 60 characters" if title.length > 60

          current = Section.new(title, m[2] ? (m[2].to_i * 60) + m[3].to_i : nil, [])
          next
        end
        phrases = phrases_of(line)
        next if phrases.empty?

        current ||= Section.new('Opening', nil, [])
        words += phrases.sum { |p| p.words.length }
        raise InputError, "the script has more than #{MAX_WORDS} words" if words > MAX_WORDS

        phrases.last.pause = [phrases.last.pause, 1.0].max # a new paragraph is a longer pause
        current.paragraphs << phrases
      end
      sections << current if current
      raise InputError, 'the script has nothing to say' if sections.all? { |s| s.paragraphs.empty? }

      sections
    end

    # Split one line into phrases at punctuation, dashes and "(pause)".
    def phrases_of(line)
      spoken = line.gsub(/\[[^\]]*\]/, ' ') # directions like [ON SCREEN: map] are not read out
                   .gsub(/[*_`>]/, ' ')     # simple Markdown emphasis
      phrases = []
      current = []
      spoken.split(/\s+/).each do |token|
        next if token.empty?

        if token.casecmp?('(pause)') || token == '/'
          close(phrases, current, 1.0)
          current = []
          next
        end
        if DASHES.include?(token)
          close(phrases, current, 0.4)
          current = []
          next
        end
        core = token.gsub(/\A[("'“‘]+/, '')
        trailing = core[/[.,;:!?)"'”’]+\z/] || ''
        core = core.delete_suffix(trailing)
        core = core.delete_suffix('.') if core.match?(/\d\.\z/)
        next if core.empty? && trailing.empty?

        current << Word.new(core, Spoken.token_syllables(core)) unless core.empty?
        mark = trailing.delete(')"\'”’')[-1]
        next unless mark && PAUSES.key?(mark)

        close(phrases, current, PAUSES[mark])
        current = []
      end
      close(phrases, current, 0.0)
      phrases
    end

    def close(phrases, words, pause)
      if words.empty?
        phrases.last.pause = [phrases.last.pause, pause].max unless phrases.empty?
        return
      end
      phrases << Phrase.new(words.dup, pause)
    end
  end
end
