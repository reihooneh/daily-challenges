# frozen_string_literal: true

module Crosscue
  # A problem with the show file. The message names the line and never repeats its text.
  class ShowError < StandardError; end

  Show = Struct.new(:name, :width, :depth, :tempo, :pace, :space, :dancers, :formations, keyword_init: true) do
    # Seconds per count.
    def beat
      60.0 / tempo
    end
  end

  # spots: positions anyone may take; pins: name => position for dancers who must be there.
  # The first formation has every dancer pinned (it defines who is where at the start).
  Formation = Struct.new(:name, :counts, :spots, :pins, :line, keyword_init: true)

  # Reads a show file strictly: fixed line forms, ranges on every number, bounded sizes.
  #
  #   show Spring recital opening
  #   stage 10 x 8          # metres wide x deep
  #   tempo 120             # counts per minute
  #   pace 1.4              # fastest comfortable walk, m/s
  #   space 0.6             # closest two moving dancers may pass, m
  #   formation V
  #     Ava 5.0 6.5         # the first formation names every dancer
  #   formation Two lines in 8 counts
  #     spot 2.0 5.0        # anyone may end here
  #     Hana 8.0 3.0        # Hana must end here
  module Parser
    MAX_BYTES = 64 * 1024
    MAX_LINE = 200
    MAX_DANCERS = 40
    MAX_FORMATIONS = 12

    LABEL = /\A[\p{L}\p{N}][\p{L}\p{N} .,'&()-]{0,59}\z/
    DANCER = /\A[\p{Lu}][\p{L}'-]{0,19}\z/
    NUM = /\A\d{1,3}(?:\.\d{1,3})?\z/
    HIDDEN = /[\p{Cc}&&[^\t]]|[‎‏‪-‮⁦-⁩]/

    module_function

    def parse(text)
      raise ShowError, 'the show file is larger than 64 KB' if text.bytesize > MAX_BYTES
      raise ShowError, 'the show file is not valid UTF-8 text' unless text.valid_encoding?

      show = { name: 'Show', width: nil, depth: nil, tempo: 120.0, pace: 1.2, space: 0.6 }
      formations = []
      text.split(/\r?\n/, -1).each_with_index do |raw, i|
        n = i + 1
        raise ShowError, "line #{n} is longer than #{MAX_LINE} characters" if raw.length > MAX_LINE
        raise ShowError, "line #{n} contains control or hidden direction characters" if raw.match?(HIDDEN)

        line = raw.sub(/#.*/, '').strip.gsub(/[ \t]+/, ' ')
        next if line.empty?

        word, rest = line.split(' ', 2)
        rest ||= ''
        case word
        when 'show'
          raise ShowError, "line #{n}: show names are letters, digits, spaces and simple punctuation" unless rest.match?(LABEL)

          show[:name] = rest
        when 'stage'
          m = rest.match(/\A(\S+) ?x ?(\S+)\z/) or raise ShowError, "line #{n}: write the stage as 'stage WIDTH x DEPTH'"
          show[:width] = number(m[1], 2, 60, 'stage width', n)
          show[:depth] = number(m[2], 2, 60, 'stage depth', n)
        when 'tempo' then show[:tempo] = number(rest, 40, 240, 'tempo', n)
        when 'pace' then show[:pace] = number(rest, 0.2, 5, 'pace', n)
        when 'space' then show[:space] = number(rest, 0, 3, 'space', n)
        when 'formation'
          raise ShowError, "line #{n}: more than #{MAX_FORMATIONS} formations" if formations.size >= MAX_FORMATIONS

          formations << formation_header(rest, n, formations.empty?)
        else
          raise ShowError, "line #{n}: positions come after a formation line" if formations.empty?

          position(formations.last, word, rest, n)
        end
      end
      finish(show, formations)
    end

    def formation_header(rest, n, first)
      m = rest.match(/\A(.+?)(?: in (\d{1,2}) counts?)?\z/)
      name = m[1]
      raise ShowError, "line #{n}: formation names are letters, digits, spaces and simple punctuation" unless name.match?(LABEL)

      counts = m[2]&.to_i
      raise ShowError, "line #{n}: the first formation is where everyone starts, so it takes no counts" if first && counts
      raise ShowError, "line #{n}: say how long the change takes, e.g. 'formation Lines in 8 counts'" if !first && counts.nil?
      raise ShowError, "line #{n}: a change takes 1 to 64 counts" if counts && !counts.between?(1, 64)

      Formation.new(name: name, counts: counts, spots: [], pins: {}, line: n)
    end

    def position(formation, word, rest, n)
      parts = rest.split(' ')
      raise ShowError, "line #{n}: a position is 'NAME X Y' or 'spot X Y'" unless parts.size == 2

      x = number(parts[0], 0, 60, 'x', n)
      y = number(parts[1], 0, 60, 'y', n)
      if word == 'spot'
        raise ShowError, "line #{n}: the first formation must name each dancer, not spots" if formation.counts.nil?

        formation.spots << [x, y]
      else
        raise ShowError, "line #{n}: dancer names are one word starting with a capital letter" unless word.match?(DANCER)
        raise ShowError, "line #{n}: #{word} is placed twice in this formation" if formation.pins.key?(word)

        formation.pins[word] = [x, y]
      end
    end

    def finish(show, formations)
      raise ShowError, "the show needs a 'stage WIDTH x DEPTH' line" unless show[:width]
      raise ShowError, 'the show needs at least two formations' if formations.size < 2

      dancers = formations.first.pins.keys
      raise ShowError, 'the first formation needs at least two dancers' if dancers.size < 2
      raise ShowError, "more than #{MAX_DANCERS} dancers" if dancers.size > MAX_DANCERS

      formations.each do |f|
        unknown = f.pins.keys - dancers
        raise ShowError, "line #{f.line}: #{unknown.first} isn't in the first formation" unless unknown.empty?
        unless f.spots.size + f.pins.size == dancers.size
          raise ShowError, "line #{f.line}: formation '#{f.name}' has #{f.spots.size + f.pins.size} places for #{dancers.size} dancers"
        end

        (f.spots + f.pins.values).each do |x, y|
          next if x <= show[:width] && y <= show[:depth]

          raise ShowError, "line #{f.line}: formation '#{f.name}' has a place off the stage"
        end
      end
      Show.new(**show, dancers: dancers, formations: formations)
    end

    def number(text, low, high, what, n)
      raise ShowError, "line #{n}: #{what} must be a plain number" unless text.to_s.match?(NUM)

      v = text.to_f
      raise ShowError, "line #{n}: #{what} must be between #{fmt(low)} and #{fmt(high)}" unless v.between?(low, high)

      v
    end

    def fmt(v)
      v == v.to_i ? v.to_i.to_s : v.to_s
    end
  end
end
