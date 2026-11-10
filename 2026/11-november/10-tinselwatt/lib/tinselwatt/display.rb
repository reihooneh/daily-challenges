# frozen_string_literal: true

module Tinselwatt
  # A problem with a display file. Messages name the line, never repeat its text.
  class InputError < StandardError; end

  Circuit = Struct.new(:id, :breaker, :load, keyword_init: true)
  Outlet = Struct.new(:id, :circuit, :x, :y, :rcd, keyword_init: true)
  Light = Struct.new(:id, :watts, :x, :y, :chain_limit, :outside, keyword_init: true)
  Cord = Struct.new(:index, :length, :amps, keyword_init: true) do
    # Copper conductor size for a cord of this rating (mm²): typical flexible-cord sizes.
    def area
      case amps
      when 0..7.5 then 0.75
      when 7.5..10 then 1.0
      when 10..13 then 1.31
      when 13..16 then 1.5
      else 2.5
      end
    end

    # Resistance there and back, ohms (copper: 0.0172 Ω·mm²/m).
    def resistance
      2 * length * 0.0172 / area
    end
  end

  # Everything about one Christmas light display: the supply, circuits, outlets, lights and cords.
  class Display
    LIMITS = { bytes: 32 * 1024, lines: 400, circuits: 12, outlets: 12, lights: 24, cords: 30 }.freeze
    NAME = /\A[a-z][a-z0-9-]{0,23}\z/
    NUMBER = /\A\d{1,5}(\.\d{1,3})?\z/

    attr_reader :title, :voltage, :circuits, :outlets, :lights, :cords

    def self.parse(text)
      new.tap { |d| d.send(:read, text) }
    end

    # Watts a socket or power board may carry: 10 A at 230 V, 15 A at 120 V.
    def outlet_watts
      voltage == 230 ? 2400 : 1800
    end

    # Watts a circuit may carry for hours on end: 80 % of its breaker.
    def circuit_watts(circuit)
      (0.8 * circuit.breaker * voltage).floor
    end

    private

    def fail!(line, message)
      raise InputError, (line.positive? ? "line #{line}: #{message}" : message)
    end

    def number(text, line, lo, hi, what)
      fail!(line, "#{what} must be a number") unless text&.match?(NUMBER)
      v = text.to_f
      fail!(line, "#{what} must be between #{lo} and #{hi}") unless v.between?(lo, hi)
      v
    end

    def name(text, line, what)
      fail!(line, "#{what} is 1-24 lowercase letters, digits or hyphens, starting with a letter") unless text&.match?(NAME)
      text
    end

    def read(text)
      fail!(0, 'the display must be text') unless text.is_a?(String)
      fail!(0, "the display is larger than #{LIMITS[:bytes] / 1024} KB") if text.bytesize > LIMITS[:bytes]
      fail!(0, 'the display is not valid UTF-8') unless text.dup.force_encoding('UTF-8').valid_encoding?
      text = text.dup.force_encoding('UTF-8')
      fail!(0, 'the display contains control or invisible formatting characters') if text.match?(/[\u0000-\u0008\u000b-\u001f\u007f\u200b-\u200f\u202a-\u202e\u2066-\u2069]/)
      lines = text.split(/\r?\n/)
      fail!(0, "the display has more than #{LIMITS[:lines]} lines") if lines.size > LIMITS[:lines]

      @title = 'My display'
      @voltage = 230
      @circuits = {}
      @outlets = {}
      @lights = {}
      @cords = []
      seen = {}
      lines.each_with_index do |raw, k|
        line = k + 1
        words = raw.sub(/#.*/, '').split
        next if words.empty?

        key = words.shift.delete_suffix(':')
        if %w[title voltage].include?(key)
          fail!(line, "#{key} is given twice") if seen[key]
          seen[key] = true
        end
        case key
        when 'title' then read_title(words, line)
        when 'voltage' then read_voltage(words, line)
        when 'circuit' then read_circuit(words, line)
        when 'outlet' then read_outlet(words, line)
        when 'light' then read_light(words, line)
        when 'cord' then read_cord(words, line)
        else fail!(line, 'unknown line (use title, voltage, circuit, outlet, light or cord)')
        end
      end
      check
    end

    def read_title(words, line)
      t = words.join(' ')
      fail!(line, 'a title is 1-60 letters, digits, spaces and simple punctuation') unless t.match?(/\A[\p{L}\p{N} ',.&()-]{1,60}\z/)
      @title = t
    end

    def read_voltage(words, line)
      fail!(line, 'voltage is 230 or 120') unless words.size == 1 && %w[230 120].include?(words[0])
      @voltage = words[0].to_i
    end

    # Reads "key value" pairs after the leading words; flags are words with no value.
    def pairs(words, line, keys, flags = [])
      out = {}
      i = 0
      while i < words.size
        w = words[i]
        if flags.include?(w)
          out[w] = true
          i += 1
        elsif keys.include?(w)
          fail!(line, "#{w} is given twice") if out.key?(w)
          n = w == 'at' ? 2 : 1
          vals = words[i + 1, n]
          fail!(line, "#{w} needs #{n == 2 ? 'two numbers' : 'a value'}") if vals.nil? || vals.size < n
          out[w] = n == 2 ? vals : vals[0]
          i += 1 + n
        else
          fail!(line, "unexpected word #{i + 1} (expected #{(keys + flags).join(', ')})")
        end
      end
      out
    end

    def place(p, line)
      fail!(line, 'give a position: at X Y (metres)') unless p['at']
      [number(p['at'][0], line, 0, 200, 'x'), number(p['at'][1], line, 0, 200, 'y')]
    end

    def read_circuit(words, line)
      id = name(words.shift, line, 'a circuit name')
      fail!(line, 'that circuit is already defined') if @circuits.key?(id)
      fail!(line, "at most #{LIMITS[:circuits]} circuits") if @circuits.size >= LIMITS[:circuits]
      p = pairs(words, line, %w[breaker load])
      fail!(line, 'give the breaker rating: breaker AMPS') unless p['breaker']
      @circuits[id] = Circuit.new(id: id, breaker: number(p['breaker'], line, 5, 32, 'breaker'),
                                  load: p['load'] ? number(p['load'], line, 0, 7000, 'load') : 0.0)
    end

    def read_outlet(words, line)
      id = name(words.shift, line, 'an outlet name')
      fail!(line, 'that outlet is already defined') if @outlets.key?(id)
      fail!(line, "at most #{LIMITS[:outlets]} outlets") if @outlets.size >= LIMITS[:outlets]
      p = pairs(words, line, %w[circuit at], %w[rcd])
      fail!(line, 'say which circuit: circuit NAME') unless p['circuit']
      x, y = place(p, line)
      @outlets[id] = Outlet.new(id: id, circuit: name(p['circuit'], line, 'a circuit name'), x: x, y: y, rcd: p['rcd'] || false)
    end

    def read_light(words, line)
      id = name(words.shift, line, 'a light name')
      fail!(line, 'that light is already defined') if @lights.key?(id)
      fail!(line, "at most #{LIMITS[:lights]} lights") if @lights.size >= LIMITS[:lights]
      p = pairs(words, line, %w[watts at chain-limit], %w[inside])
      fail!(line, 'give its power: watts W') unless p['watts']
      x, y = place(p, line)
      limit = p['chain-limit'] ? number(p['chain-limit'], line, 1, 3000, 'chain-limit') : nil
      @lights[id] = Light.new(id: id, watts: number(p['watts'], line, 1, 3000, 'watts'), x: x, y: y,
                              chain_limit: limit, outside: !p['inside'])
    end

    def read_cord(words, line)
      length = number(words.shift, line, 1, 50, 'a cord length')
      p = pairs(words, line, %w[rated count])
      fail!(line, 'give its rating: rated AMPS') unless p['rated']
      amps = number(p['rated'], line, 5, 20, 'rated')
      count = p['count'] ? number(p['count'], line, 1, 10, 'count').to_i : 1
      fail!(line, "at most #{LIMITS[:cords]} cords") if @cords.size + count > LIMITS[:cords]
      count.times { @cords << Cord.new(index: @cords.size, length: length, amps: amps) }
    end

    def check
      fail!(0, 'add at least one circuit, outlet and light') if @circuits.empty? || @outlets.empty? || @lights.empty?
      @outlets.each_value do |o|
        fail!(0, "outlet #{o.id} is on circuit #{o.circuit}, which isn't defined") unless @circuits.key?(o.circuit)
      end
      @lights.each_value do |l|
        next unless l.chain_limit && l.watts > l.chain_limit

        fail!(0, "light #{l.id} draws #{l.watts.round} W, more than its #{l.chain_limit.round} W chain limit: feed it from two ends as two lights")
      end
    end
  end
end
