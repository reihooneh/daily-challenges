# frozen_string_literal: true

module Crosscue
  # One change between formations, worked out.
  Change = Struct.new(:from_name, :to_name, :counts, :moves, :longest, :total, :needed_counts, :conflicts,
                      keyword_init: true)

  # Plans every change in the show, carrying each dancer's position from one formation to the next.
  module Planner
    module_function

    def plan(show)
      where = show.formations.first.pins.dup
      show.formations.each_cons(2).map do |before, after|
        change = plan_change(show, before, after, where)
        change.moves.each { |m| where[m.dancer] = m.to }
        change
      end
    end

    def plan_change(show, before, after, where)
      dancers = show.dancers
      places = after.spots.map { |s| [s, nil] } + after.pins.map { |name, s| [s, name] }
      cost = dancers.map { |d| places.map { |(spot, _)| dist(where[d], spot) } }
      # A pinned place can only go to its dancer, and a pinned dancer only to their place.
      allowed = dancers.map do |d|
        places.map { |(_, owner)| owner.nil? ? !after.pins.key?(d) : owner == d }
      end
      result = Assignment.plan(cost, allowed)
      counts = after.counts
      moves = dancers.each_with_index.map do |d, i|
        Move.new(dancer: d, from: where[d], to: places[result[:assignment][i]][0], start: 0.0, finish: counts.to_f)
      end
      needed = ->(metres) { (metres / show.pace / show.beat).ceil }
      remaining = Paths.stagger!(moves, counts, show.space, needed)
      Change.new(from_name: before.name, to_name: after.name, counts: counts, moves: moves, longest: result[:longest],
                 total: result[:total], needed_counts: needed.call(result[:longest]), conflicts: remaining)
    end

    def dist(a, b)
      Math.hypot(a[0] - b[0], a[1] - b[1])
    end
  end
end
