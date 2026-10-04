# frozen_string_literal: true

module Rankle
  # Raised for any problem with the ballot file. The message is safe to print.
  class InputError < StandardError; end

  # One group of identical ballots: `count` voters who all ranked `ranking`.
  Ballot = Struct.new(:count, :ranking)

  # Reads ballots from text such as:
  #
  #   # comments and blank lines are ignored
  #   18: Ana > Dev > Eli > Cai > Bo
  #   Bo > Eli            (no count means one voter; unlisted candidates rank last)
  #
  # Everything here treats the text as hostile: sizes are capped and names are
  # restricted to ordinary printable characters.
  module Ballots
    MAX_BYTES = 1_000_000
    MAX_LINES = 10_000
    MAX_CANDIDATES = 20
    MAX_NAME_LENGTH = 40
    MAX_VOTERS = 1_000_000_000

    # Letters, digits, spaces and a few safe punctuation marks. No control
    # characters, so a name can never smuggle terminal escape codes into output.
    NAME = /\A[\p{L}\p{N}][\p{L}\p{N} .'_-]*\z/

    # Control and invisible formatting characters (tab is allowed as a space).
    CONTROL = /[[\p{Cc}\p{Cf}]&&[^\t]]/

    module_function

    # Returns [candidates, ballots]. Candidates are in order of first appearance.
    def parse(text)
      raise InputError, 'input is not text' unless text.is_a?(String)
      raise InputError, "input is larger than #{MAX_BYTES} bytes" if text.bytesize > MAX_BYTES

      text = text.dup.force_encoding(Encoding::UTF_8)
      raise InputError, 'input is not valid UTF-8 text' unless text.valid_encoding?

      lines = text.split(/\r?\n/, -1)
      raise InputError, "more than #{MAX_LINES} lines" if lines.size > MAX_LINES

      candidates = []
      ballots = []
      lines.each_with_index do |line, index|
        # Checked on the raw line, before anything is trimmed away.
        raise InputError, "line #{index + 1}: control characters are not allowed" if CONTROL.match?(line)

        line = line.sub(/#.*/, '').strip
        next if line.empty?

        ballots << parse_line(line, index + 1, candidates)
      end

      raise InputError, 'no ballots found' if ballots.empty?
      raise InputError, 'an election needs at least two candidates' if candidates.size < 2

      total = ballots.sum(&:count)
      raise InputError, "more than #{MAX_VOTERS} voters in total" if total > MAX_VOTERS

      [candidates, ballots]
    end

    def parse_line(line, number, candidates)
      count = 1
      if (match = line.match(/\A(\d{1,10})\s*:\s*(.*)\z/))
        count = match[1].to_i
        line = match[2]
        raise InputError, "line #{number}: count must be between 1 and #{MAX_VOTERS}" unless count.between?(1, MAX_VOTERS)
      end

      ranking = line.split('>', -1).map { |name| name.strip.squeeze(' ') }
      raise InputError, "line #{number}: empty candidate name" if ranking.any?(&:empty?)

      ranking.each do |name|
        unless name.length <= MAX_NAME_LENGTH && NAME.match?(name)
          raise InputError, "line #{number}: invalid candidate name (letters, digits, spaces and . ' _ - only, " \
                            "#{MAX_NAME_LENGTH} characters at most)"
        end
      end
      raise InputError, "line #{number}: a candidate is ranked twice" if ranking.uniq.size != ranking.size

      ranking.each do |name|
        next if candidates.include?(name)

        candidates << name
        raise InputError, "more than #{MAX_CANDIDATES} candidates" if candidates.size > MAX_CANDIDATES
      end
      Ballot.new(count, ranking.freeze)
    end
  end
end
