# frozen_string_literal: true

require_relative 'analysis'

module Rankle
  # Turns the analysis into plain text. Returns a string; prints nothing.
  module Report
    module_function

    def render(candidates, ballots)
      results = Analysis.results(candidates, ballots)
      lines = []
      voters = ballots.sum(&:count)
      lines << "#{voters} voters, #{candidates.size} candidates: #{candidates.join(', ')}"
      lines << ''
      width = results.keys.map(&:length).max
      results.each { |name, winners| lines << "  #{name.ljust(width)}  #{describe(winners)}" }
      lines << ''
      lines << verdict(results)
      lines.concat(paradoxes(candidates, ballots, results))
      lines.concat(spoiler_lines(Analysis.spoilers(candidates, ballots)))
      "#{lines.join("\n")}\n"
    end

    def describe(winners)
      case winners.size
      when 0 then '(no winner: nobody beats everyone one-on-one)'
      when 1 then winners.first
      else "tie: #{winners.join(', ')}"
      end
    end

    def verdict(results)
      distinct = results.values.reject(&:empty?).map(&:sort).uniq
      if distinct.size <= 1 && results.values.none?(&:empty?)
        'All five rules agree. This result is hard to argue with.'
      elsif distinct.size <= 1
        'Every rule that produced a winner agrees.'
      else
        "The same ballots produce #{distinct.size} different outcomes. The rule decides the election."
      end
    end

    def paradoxes(candidates, ballots, results)
      lines = []
      if (cycle = Analysis.cycle(candidates, ballots))
        a, b, c = cycle
        lines << "Cycle: #{a} beats #{b}, #{b} beats #{c}, and #{c} beats #{a}. " \
                 'The group has no consistent preference (the Condorcet paradox).'
      end
      loser = Analysis.condorcet_loser(candidates, ballots)
      if loser
        elected_by = results.select { |_, winners| winners == [loser] }.keys
        unless elected_by.empty?
          lines << "Warning: #{loser} loses one-on-one to every other candidate, " \
                   "yet wins under #{elected_by.join(' and ')}."
        end
      end
      lines
    end

    def spoiler_lines(spoilers)
      return ['', 'No spoilers: removing any losing candidate leaves every result unchanged.'] if spoilers.empty?

      lines = ['', 'Spoilers (a loser whose presence changes the winner):']
      spoilers.each do |s|
        lines << "  #{s.method_name}: without #{s.candidate}, the result changes from " \
                 "#{describe(s.before)} to #{describe(s.after)}."
      end
      lines
    end
  end
end
