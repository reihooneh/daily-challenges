# frozen_string_literal: true

module Crosscue
  # One dancer's straight-line move during a change: still until `start`, walking at a steady
  # speed, arriving exactly at `finish` (both in counts from the start of the change).
  Move = Struct.new(:dancer, :from, :to, :start, :finish, keyword_init: true) do
    def distance
      Math.hypot(to[0] - from[0], to[1] - from[1])
    end

    def at(t)
      return from if t <= start
      return to if t >= finish || finish <= start

      f = (t - start) / (finish - start)
      [from[0] + ((to[0] - from[0]) * f), from[1] + ((to[1] - from[1]) * f)]
    end

    def moving?
      distance > 1e-9
    end
  end

  # Where two moving dancers come closest, worked out exactly: between the moments when either
  # starts or stops, both move in straight lines at steady speeds, so the distance between them
  # is the square root of a quadratic in time, minimised in closed form.
  module Paths
    module_function

    # Returns [closest distance, count at which it happens].
    def closest(a, b, counts)
      marks = [0.0, a.start, a.finish, b.start, b.finish, counts.to_f].map { |m| m.clamp(0.0, counts.to_f) }.uniq.sort
      best = [Float::INFINITY, 0.0]
      marks.each_cons(2) do |t0, t1|
        p0 = diff(a.at(t0), b.at(t0))
        p1 = diff(a.at(t1), b.at(t1))
        vel = [p1[0] - p0[0], p1[1] - p0[1]]
        vv = (vel[0]**2) + (vel[1]**2)
        f = vv < 1e-15 ? 0.0 : (-((p0[0] * vel[0]) + (p0[1] * vel[1]))).fdiv(vv).clamp(0.0, 1.0)
        d = Math.hypot(p0[0] + (vel[0] * f), p0[1] + (vel[1] * f))
        best = [d, t0 + ((t1 - t0) * f)] if d < best[0] - 1e-12
      end
      [best[0], marks.size == 1 ? 0.0 : best[1]]
    end

    def diff(p, q)
      [p[0] - q[0], p[1] - q[1]]
    end

    # Pairs that pass closer than `space` while moving (closer than where they start and end, so
    # partners who begin and finish side by side aren't flagged).
    def conflicts(moves, counts, space)
      found = []
      moves.combination(2) do |a, b|
        next unless a.moving? || b.moving?

        d, t = closest(a, b, counts)
        ends = [Math.hypot(*diff(a.from, b.from)), Math.hypot(*diff(a.to, b.to))].min
        found << { pair: [a.dancer, b.dancer], distance: d, count: t } if d < space - 1e-9 && d < ends - 1e-9
      end
      found
    end

    # Clears near-misses by changing one dancer's timing: either they wait a few counts before
    # going, or they hurry and arrive a few counts early. Either way they walk the same line, just
    # faster, so it must stay within their pace. Tries the dancer with the shorter walk first and the
    # smallest change that works without creating a new near-miss. Returns what's left.
    def stagger!(moves, counts, space, max_speed_counts)
      4.times do
        remaining = conflicts(moves, counts, space)
        return remaining if remaining.empty?

        progress = false
        remaining.each do |c|
          pair = moves.select { |m| c[:pair].include?(m.dancer) }.sort_by(&:distance)
          pair.each do |m|
            before = [m.start, m.finish]
            cleared = retime(m, moves, counts, space, max_speed_counts)
            progress ||= cleared || improved?(m, before)
            break if cleared
          end
        end
        break unless progress
      end
      conflicts(moves, counts, space)
    end

    # Tries every timing change for one dancer, smallest first. If one clears all their
    # near-misses, keep it and return true. Otherwise keep the one that leaves them the most room
    # (so changing the other dancer next round can finish the job) and return whether anything
    # improved.
    def retime(move, moves, counts, space, max_speed_counts)
      room = lambda { conflicts(moves, counts, space).select { |o| o[:pair].include?(move.dancer) }.map { |o| o[:distance] }.min }
      original = [move.start, move.finish]
      best = [room.call || Float::INFINITY, original]
      (1...counts).each do |k|
        next if counts - k < max_speed_counts.call(move.distance)

        [[k.to_f, counts.to_f], [0.0, (counts - k).to_f]].each do |timing|
          move.start, move.finish = timing
          left = room.call
          return true if left.nil?

          best = [left, timing] if left > best[0] + 1e-9
        end
      end
      move.start, move.finish = best[1]
      false
    end

    # True if retiming this dancer gave them more room (even without clearing everything).
    def improved?(move, before)
      [move.start, move.finish] != before
    end
  end
end
