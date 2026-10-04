# frozen_string_literal: true

require_relative 'rankle/ballots'
require_relative 'rankle/methods'
require_relative 'rankle/analysis'
require_relative 'rankle/report'

# Rankle: one set of ranked ballots, five voting rules, and the spoilers.
module Rankle
  VERSION = '1.0.0'

  USAGE = <<~TEXT
    Usage: rankle BALLOT_FILE
           rankle -          (read ballots from standard input)

    Each line is a group of identical ballots, best choice first:
        18: Ana > Dev > Eli > Cai > Bo
    The count is optional. Lines starting with # are comments.

    Exit codes: 0 all rules agree, 1 the rules disagree, 2 error.
  TEXT

  module_function

  # Runs the command line. Returns the exit code; never raises for bad input.
  def run(argv, stdin: $stdin, out: $stdout, err: $stderr)
    if %w[-h --help].include?(argv.first) && argv.size == 1
      out.puts USAGE
      return 0
    end
    if argv == ['--version']
      out.puts "rankle #{VERSION}"
      return 0
    end
    if argv.size != 1
      err.puts USAGE
      return 2
    end

    candidates, ballots = Ballots.parse(read(argv.first, stdin))
    out.print Report.render(candidates, ballots)
    agreed = Analysis.results(candidates, ballots).values.map(&:sort).uniq.size == 1
    agreed ? 0 : 1
  rescue InputError => e
    err.puts "rankle: #{e.message}"
    2
  end

  # Reads at most MAX_BYTES + 1 bytes, so a huge file is never loaded in full.
  def read(path, stdin)
    limit = Ballots::MAX_BYTES + 1
    return stdin.read(limit) || '' if path == '-'
    raise InputError, 'cannot read that file' unless File.file?(path) && File.readable?(path)

    File.open(path, 'rb') { |file| file.read(limit) || '' }
  rescue SystemCallError, ArgumentError
    raise InputError, 'cannot read that file'
  end
end
