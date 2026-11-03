# frozen_string_literal: true

module Rungwise
  class PolicyError < StandardError; end

  # One rung of the no-claim-bonus ladder: its name, the discount it gives, and where one claim
  # sends you. A year without a claim moves you one rung up (the next line in the file).
  Level = Struct.new(:name, :discount, :after_claim)

  # The insurance policy and the driver, as read from the file.
  Policy = Struct.new(:title, :premium, :excess, :chance, :median, :spread, :years, :interest,
                      :start, :protection, :levels, keyword_init: true)

  # Reads the policy file. Every line has a fixed shape and every number a range; errors give the
  # line number and what was expected, never the line itself.
  module Parser
    MAX_BYTES = 32 * 1024
    MAX_LINE = 200
    MAX_LEVELS = 30
    NAME = /\A[\p{L}\p{N}][\p{L}\p{N} '.,&()%-]{0,39}\z/
    HIDDEN = /[\p{Cc}\p{Cf}]/
    NUMBER = /\A\$?(\d{1,7}(?:\.\d{1,4})?)(%?)\z/

    module_function

    def fail!(line, msg)
      raise PolicyError, (line.positive? ? "line #{line}: #{msg}" : msg)
    end

    # A number in a range; "8%" means 0.08 when percent is allowed.
    def number(text, line, what, low, high, percent: false)
      m = NUMBER.match(text.to_s.delete(','))
      fail!(line, "#{what} must be a number, like 1200 or 8%") unless m
      fail!(line, "#{what} must be a plain number, not a percentage") if m[2] == '%' && !percent
      value = m[1].to_f
      value /= 100 if m[2] == '%'
      fail!(line, "#{what} must be from #{low} to #{high}") unless value.between?(low, high)
      value
    end

    def name(text, line, what)
      t = text.to_s.strip.squeeze(' ')
      fail!(line, "#{what} uses letters, digits, spaces and ' . , & ( ) % - (up to 40)") unless NAME.match?(t)
      t
    end

    SETTINGS = {
      'premium' => ['the base premium', 1, 1_000_000, false],
      'excess' => ['the excess', 0, 1_000_000, false],
      'accident-chance' => ['the yearly chance of an at-fault accident', 0, 0.9, true],
      'repair-median' => ['the typical repair bill', 1, 10_000_000, false],
      'repair-spread' => ['the repair spread', 0.05, 3, false],
      'years' => ['the years to plan', 1, 30, false],
      'interest' => ['the interest rate', 0, 0.3, true],
      'protection' => ['the price of bonus protection', 0, 1_000_000, false]
    }.freeze

    def parse(text)
      fail!(0, 'the policy file is larger than 32 KB') if text.bytesize > MAX_BYTES
      fail!(0, 'the policy file is not valid UTF-8 text') unless text.valid_encoding?

      values = { title: 'My insurance', interest: 0.0, protection: nil }
      levels = []
      claim_to = []
      seen = {}
      start_name = nil
      start_line = 0
      text.delete_prefix("\uFEFF").split("\n", -1).each_with_index do |raw, i|
        n = i + 1
        raw = raw.delete_suffix("\r")
        fail!(n, "is longer than #{MAX_LINE} characters") if raw.length > MAX_LINE
        fail!(n, 'contains a control or invisible formatting character') if HIDDEN.match?(raw.delete("\t"))
        line = raw.split('#', 2).first.to_s.strip.squeeze(' ')
        next if line.empty?

        head, rest = line.split(' ', 2)
        if head != 'level'
          fail!(n, "'#{head}' comes once") if seen[head]
          seen[head] = true
        end
        case head
        when 'policy' then values[:title] = name(rest, n, 'the policy name')
        when 'start' then start_name = name(rest, n, 'the starting level')
                          start_line = n
        when 'level'
          m = /\A(.+?) discount (\S+) claim-to (.+)\z/.match(rest.to_s)
          fail!(n, "write a level like 'level Rating 3 discount 40% claim-to Rating 5'") unless m
          fail!(n, "at most #{MAX_LEVELS} levels") if levels.size >= MAX_LEVELS
          lname = name(m[1], n, 'a level name')
          fail!(n, 'two levels have the same name') if levels.any? { |l| l.name == lname }
          levels << Level.new(lname, number(m[2], n, 'a discount', 0, 0.95, percent: true), nil)
          claim_to << [name(m[3], n, 'the level a claim sends you to'), n]
        when *SETTINGS.keys
          what, low, high, percent = SETTINGS[head]
          values[head.tr('-', '_').to_sym] = number(rest, n, what, low, high, percent: percent)
        else
          fail!(n, 'lines start with policy, premium, excess, accident-chance, repair-median, repair-spread, years, interest, protection, start or level')
        end
      end

      fail!(0, 'the policy needs at least two levels') if levels.size < 2
      %w[premium excess accident-chance repair-median years].each do |k|
        fail!(0, "the policy needs a '#{k}' line") unless seen[k]
      end
      fail!(0, 'the years to plan must be a whole number') unless (values[:years] % 1).zero?
      claim_to.each_with_index do |(target, n), i|
        j = levels.index { |l| l.name == target }
        fail!(n, 'a claim sends you to a level that is not listed') unless j
        fail!(n, 'a claim can only keep you where you are or move you down') if j > i
        levels[i].after_claim = j
      end
      start = start_name ? levels.index { |l| l.name == start_name } : levels.size - 1
      fail!(start_line, 'the starting level is not listed') unless start

      Policy.new(title: values[:title], premium: values[:premium], excess: values[:excess],
                 chance: values[:accident_chance], median: values[:repair_median],
                 spread: values[:repair_spread] || 0.8, years: values[:years].to_i,
                 interest: values[:interest], start: start, protection: values[:protection], levels: levels)
    end
  end
end
