# frozen_string_literal: true

module Rankle
  # Five ways to pick a winner from the same ranked ballots.
  #
  # Every method takes (candidates, ballots) and returns an array of winners:
  # one name normally, several for an exact tie, and none when the method
  # has no answer (a Condorcet cycle).
  module Methods
    module_function

    ALL = {
      'Plurality' => :plurality,
      'Two-round runoff' => :runoff,
      'Instant runoff' => :instant_runoff,
      'Borda count' => :borda,
      'Condorcet' => :condorcet
    }.freeze

    def winners(method_name, candidates, ballots)
      public_send(ALL.fetch(method_name), candidates, ballots)
    end

    # First choices among the candidates still standing.
    def first_choices(standing, ballots)
      tally = standing.to_h { |name| [name, 0] }
      ballots.each do |ballot|
        top = ballot.ranking.find { |name| tally.key?(name) }
        tally[top] += ballot.count if top
      end
      tally
    end

    def top_of(tally)
      best = tally.values.max
      tally.select { |_, votes| votes == best }.keys
    end

    # Most first choices wins. Everything after first place is ignored.
    def plurality(candidates, ballots)
      top_of(first_choices(candidates, ballots))
    end

    # The top two on first choices go to a second round, head to head.
    def runoff(candidates, ballots)
      tally = first_choices(candidates, ballots)
      total = tally.values.sum
      leaders = top_of(tally)
      return leaders if leaders.size == 1 && tally[leaders.first] * 2 > total
      return leaders if leaders.size > 2 # no fair way to choose two finalists

      finalists = leaders
      if finalists.size == 1
        rest = tally.reject { |name, _| name == finalists.first }
        seconds = top_of(rest)
        return leaders if seconds.size > 1 # tie for second place: stop at round one

        finalists += seconds
      end
      top_of(first_choices(finalists, ballots))
    end

    # Repeatedly eliminate the candidate with the fewest first choices and
    # move those ballots to their next choice, until someone has a majority.
    def instant_runoff(candidates, ballots)
      standing = candidates.dup
      loop do
        tally = first_choices(standing, ballots)
        total = tally.values.sum
        leaders = top_of(tally)
        return leaders if total.zero? || tally[leaders.first] * 2 > total

        fewest = tally.values.min
        losers = tally.select { |_, votes| votes == fewest }.keys
        return standing if losers.size == standing.size # everyone left is tied

        standing -= losers
      end
    end

    # Points for position: with n candidates, first place earns n-1 points,
    # second n-2, and so on. Unranked candidates earn nothing.
    def borda(candidates, ballots)
      top_of(borda_scores(candidates, ballots))
    end

    def borda_scores(candidates, ballots)
      scores = candidates.to_h { |name| [name, 0] }
      highest = candidates.size - 1
      ballots.each do |ballot|
        position = 0
        ballot.ranking.each do |name|
          next unless scores.key?(name)

          scores[name] += (highest - position) * ballot.count
          position += 1
        end
      end
      scores
    end

    # The candidate who beats every other candidate one-on-one.
    # Returns [] when there is no such candidate (a cycle or a tie).
    def condorcet(candidates, ballots)
      matrix = pairwise(candidates, ballots)
      winner = candidates.find do |a|
        candidates.all? { |b| a == b || matrix[a][b] > matrix[b][a] }
      end
      winner ? [winner] : []
    end

    # matrix[a][b] = number of voters who prefer a to b. A ranked candidate
    # is preferred to an unranked one; two unranked candidates are equal.
    def pairwise(candidates, ballots)
      matrix = candidates.to_h { |a| [a, candidates.to_h { |b| [b, 0] }] }
      ballots.each do |ballot|
        ranked = ballot.ranking.select { |name| matrix.key?(name) }
        unranked = candidates - ranked
        ranked.each_with_index do |a, i|
          (ranked[(i + 1)..] + unranked).each { |b| matrix[a][b] += ballot.count }
        end
      end
      matrix
    end
  end
end
