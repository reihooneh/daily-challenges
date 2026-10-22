# frozen_string_literal: true

module Crosscue
  # Who goes to which spot.
  #
  # First the bottleneck assignment: the smallest possible "longest walk", found by binary search
  # over the distinct distances, testing at each threshold whether everyone can be matched to a
  # spot using only walks up to that length (augmenting paths). Then, among all assignments that
  # keep within that longest walk, the Hungarian algorithm picks the one with the least walking
  # in total.
  module Assignment
    INF = Float::INFINITY

    module_function

    # cost: square matrix (dancers x spots). allowed[i][j] false forbids a pairing.
    # Returns {assignment: spot index for each dancer, longest:, total:}.
    def plan(cost, allowed = nil)
      n = cost.size
      allowed ||= Array.new(n) { Array.new(n, true) }
      candidates = []
      n.times { |i| n.times { |j| candidates << cost[i][j] if allowed[i][j] } }
      candidates = candidates.uniq.sort
      lo = 0
      hi = candidates.size - 1
      raise ArgumentError, 'no assignment is possible' if hi.negative? || !matchable?(cost, allowed, candidates[hi])

      while lo < hi
        mid = (lo + hi) / 2
        if matchable?(cost, allowed, candidates[mid])
          hi = mid
        else
          lo = mid + 1
        end
      end
      limit = candidates[lo]
      capped = Array.new(n) { |i| Array.new(n) { |j| allowed[i][j] && cost[i][j] <= limit + 1e-12 ? cost[i][j] : INF } }
      assignment = hungarian(capped)
      longest = assignment.each_with_index.map { |j, i| cost[i][j] }.max
      total = assignment.each_with_index.sum { |j, i| cost[i][j] }
      { assignment: assignment, longest: longest, total: total }
    end

    # Can every row be matched to a distinct column using only entries <= limit? (Kuhn's algorithm.)
    def matchable?(cost, allowed, limit)
      n = cost.size
      match_col = Array.new(n)
      n.times.all? do |i|
        augment(i, Array.new(n, false), match_col) { |r, c| allowed[r][c] && cost[r][c] <= limit + 1e-12 }
      end
    end

    def augment(row, seen, match_col, &ok)
      match_col.size.times do |c|
        next if seen[c] || !ok.call(row, c)

        seen[c] = true
        if match_col[c].nil? || augment(match_col[c], seen, match_col, &ok)
          match_col[c] = row
          return true
        end
      end
      false
    end

    # Minimum-cost perfect assignment (Hungarian algorithm with potentials, O(n^3)).
    # Returns the column for each row. Infinite costs are never used if avoidable.
    def hungarian(cost)
      n = cost.size
      big = cost.flatten.reject(&:infinite?).max.to_f * n + 1
      a = cost.map { |row| row.map { |v| v.infinite? ? big : v } }
      u = Array.new(n + 1, 0.0)
      v = Array.new(n + 1, 0.0)
      p = Array.new(n + 1, 0)
      way = Array.new(n + 1, 0)
      (1..n).each do |i|
        p[0] = i
        j0 = 0
        minv = Array.new(n + 1, INF)
        used = Array.new(n + 1, false)
        loop do
          used[j0] = true
          i0 = p[j0]
          delta = INF
          j1 = 0
          (1..n).each do |j|
            next if used[j]

            cur = a[i0 - 1][j - 1] - u[i0] - v[j]
            if cur < minv[j]
              minv[j] = cur
              way[j] = j0
            end
            if minv[j] < delta
              delta = minv[j]
              j1 = j
            end
          end
          (0..n).each do |j|
            if used[j]
              u[p[j]] += delta
              v[j] -= delta
            else
              minv[j] -= delta
            end
          end
          j0 = j1
          break if p[j0].zero?
        end
        loop do
          j1 = way[j0]
          p[j0] = p[j1]
          j0 = j1
          break if j0.zero?
        end
      end
      result = Array.new(n)
      (1..n).each { |j| result[p[j] - 1] = j - 1 }
      result
    end
  end
end
