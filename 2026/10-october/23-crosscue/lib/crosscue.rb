# frozen_string_literal: true

# Crosscue: who walks where between dance formations, so the change fits the music and nobody
# collides. See README.md.
require_relative 'crosscue/parser'
require_relative 'crosscue/assignment'
require_relative 'crosscue/paths'
require_relative 'crosscue/planner'
require_relative 'crosscue/report'

module Crosscue
  VERSION = '1.0.0'
end
