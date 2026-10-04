# frozen_string_literal: true

require_relative 'methods'

module Rankle
  # Looks for the things that make people argue about elections.
  module Analysis
    module_function

    Spoiler = Struct.new(:method_name, :candidate, :before, :after)

    # Winner(s) under every method: { "Plurality" => ["Ana"], ... }
    def results(candidates, ballots)
      Methods::ALL.keys.to_h { |name| [name, Methods.winners(name, candidates, ballots)] }
    end

    # A spoiler is a candidate who loses, yet whose presence changes who wins.
    # For each method, remove each loser in turn and re-run the election.
    def spoilers(candidates, ballots)
      return [] if candidates.size < 3

      found = []
      Methods::ALL.each_key do |method_name|
        before = Methods.winners(method_name, candidates, ballots)
        next if before.empty?

        (candidates - before).each do |candidate|
          after = Methods.winners(method_name, candidates - [candidate], ballots)
          found << Spoiler.new(method_name, candidate, before, after) if after.sort != before.sort
        end
      end
      found
    end

    # A cycle such as "A beats B, B beats C, C beats A", or nil.
    # Only reported when no candidate beats all the others.
    def cycle(candidates, ballots)
      return nil unless Methods.condorcet(candidates, ballots).empty?

      matrix = Methods.pairwise(candidates, ballots)
      beats = ->(a, b) { matrix[a][b] > matrix[b][a] }
      candidates.permutation(3) do |a, b, c|
        return [a, b, c] if beats.call(a, b) && beats.call(b, c) && beats.call(c, a)
      end
      nil
    end

    # The candidate who loses to every other candidate one-on-one, or nil.
    def condorcet_loser(candidates, ballots)
      matrix = Methods.pairwise(candidates, ballots)
      candidates.find do |a|
        candidates.all? { |b| a == b || matrix[a][b] < matrix[b][a] }
      end
    end
  end
end
