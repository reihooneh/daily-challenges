# frozen_string_literal: true

require_relative 'tinselwatt/display'
require_relative 'tinselwatt/planner'
require_relative 'tinselwatt/report'

# Tinselwatt plans where to plug in a Christmas light display safely.
module Tinselwatt
  module_function

  # Reads a display file (a regular file, not a link, at most 32 KB) and returns its text.
  def read_file(path)
    st = File.lstat(path)
    raise InputError, 'the display must be a regular file' unless st.file?
    raise InputError, 'the display is larger than 32 KB' if st.size > Display::LIMITS[:bytes]

    File.binread(path, Display::LIMITS[:bytes] + 1)
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP
    raise InputError, 'cannot open the display file'
  end
end
