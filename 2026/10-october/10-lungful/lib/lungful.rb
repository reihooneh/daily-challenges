# frozen_string_literal: true

require_relative 'lungful/spoken'
require_relative 'lungful/script'
require_relative 'lungful/analysis'
require_relative 'lungful/report'

# Lungful: times a script for reading aloud and finds the places you'll run out of breath.
module Lungful
  USAGE = 'usage: lungful [--rate 2.5-6] [--breath 12-40] [--marked] SCRIPT   (use - for standard input)'

  module_function

  # Reads at most MAX_BYTES + 1 bytes, so a huge file or an endless stream is refused, not loaded.
  def read_limited(path, stdin)
    data = if path == '-'
             stdin.read(Script::MAX_BYTES + 1) || ''
           else
             File.open(path, 'rb') { |f| f.read(Script::MAX_BYTES + 1) || '' }
           end
    raise InputError, "the script is larger than #{Script::MAX_BYTES / 1024} KB" if data.bytesize > Script::MAX_BYTES

    data.force_encoding(Encoding::UTF_8)
  rescue SystemCallError, IOError
    raise InputError, 'the script could not be read'
  end

  def number_option(args, i, range, message)
    value = args[i]
    raise InputError, message unless value&.match?(/\A\d{1,2}(\.\d)?\z/) && range.cover?(value.to_f)

    value.to_f
  end

  # Returns the exit code: 0 ready, 1 things to fix, 2 bad input.
  def main(args, stdin: $stdin, out: $stdout, err: $stderr)
    rate = 3.8
    limit = 24
    marked = false
    path = nil
    i = 0
    while i < args.length
      case args[i]
      when '--rate' then rate = number_option(args, i += 1, 2.5..6.0, '--rate must be a number from 2.5 to 6 syllables a second')
      when '--breath' then limit = number_option(args, i += 1, 12..40, '--breath must be a whole number from 12 to 40').to_i
      when '--marked' then marked = true
      when '-h', '--help'
        out.puts USAGE
        return 0
      else
        raise InputError, 'unknown option' if args[i].start_with?('-') && args[i] != '-'
        raise InputError, 'give exactly one script' if path

        path = args[i]
      end
      i += 1
    end
    raise InputError, 'give a script to check' unless path

    sections = Script.parse(read_limited(path, stdin))
    result = Analysis.run(sections, rate: rate, limit: limit)
    text, problems = Report.render(result, path == '-' ? 'standard input' : File.basename(path).gsub(/[^\w.\- ]/, '?'))
    out.print text
    if marked
      out.puts
      out.puts Report.marked(sections, result)
    end
    problems.zero? ? 0 : 1
  rescue InputError => e
    err.puts "lungful: #{e.message}"
    err.puts USAGE
    2
  end
end
