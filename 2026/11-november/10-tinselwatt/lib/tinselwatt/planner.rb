# frozen_string_literal: true

module Tinselwatt
  # One way to power a light: an outlet, and the cord to reach it (nil if it plugs straight in).
  Option = Struct.new(:outlet, :cord, :reach, :drop, keyword_init: true) do
    def metres
      cord ? cord.length : 0
    end
  end

  # The plan: for every light, an option or the reason it was left off.
  Plan = Struct.new(:display, :choice, :skipped, :metres, :nodes, :proven, keyword_init: true)

  # Finds the safest arrangement that powers the most watts with the least cord.
  #
  # Every light gets an outlet and one cord (or none, if it is right beside the outlet). Hard rules:
  # each circuit stays within 80 % of its breaker counting what's already on it; each outlet within
  # its socket rating; each cord carries no more than it is rated for and drops at most 3 % of the
  # voltage; lights outside only use outlets with an RCD (GFCI); each cord is used once. Among the
  # arrangements that obey them, it powers as many watts as it can, then lays the fewest metres of
  # cord, then keeps the busiest circuit as lightly loaded as possible.
  #
  # The search is branch and bound: lights with the fewest choices go first, and a branch is dropped
  # as soon as its cord so far plus the least each remaining light could need can't beat the best
  # plan found.
  class Planner
    MAX_DROP = 0.03
    PLUG_REACH = 1.5 # metres: a light this close plugs straight in
    NODE_LIMIT = 3_000_000
    SKIP = 100_000.0 # cost of leaving a light off, plus 10 per watt: always worse than any cord

    attr_reader :display, :options, :reasons

    def initialize(display)
      @display = display
      @options = {}
      @reasons = {}
      display.lights.each_value { |l| build_options(l) }
    end

    # How far a cord must run: along the ground and walls (not as the crow flies), with a metre
    # spare to rise to the socket and to the light.
    def self.reach(light, outlet)
      ((light.x - outlet.x).abs + (light.y - outlet.y).abs) * 1.1 + 1.0
    end

    def plan
      lights = display.lights.values.sort_by { |l| [@options[l.id].size, -l.watts, l.id] }
      @order = lights
      @best_cost = Float::INFINITY
      @best = nil
      @nodes = 0
      @circuit_load = display.circuits.transform_values(&:load)
      @outlet_load = Hash.new(0.0)
      @used = 0
      @floor = suffix_floors(lights)
      @twins = display.cords.map { |c| display.cords.select { |d| d.index < c.index && d.length == c.length && d.amps == c.amps }.map(&:index) }
      search(0, 0.0, [])
      choice = {}
      skipped = {}
      lights.each_with_index do |l, k|
        opt = @best[k]
        if opt
          choice[l.id] = opt
        else
          skipped[l.id] = @reasons[l.id] || remedy(l, choice)
        end
      end
      Plan.new(display: display, choice: choice, skipped: skipped, metres: choice.values.sum(&:metres),
               nodes: @nodes, proven: @nodes < NODE_LIMIT)
    end

    # Scores a complete arrangement (lights in @order; nil = left off). Public for the tests.
    def cost_of(choices)
      metres = 0.0
      skipped = 0.0
      @order.each_with_index do |l, k|
        if choices[k]
          metres += choices[k].metres
        else
          skipped += SKIP + 10 * l.watts
        end
      end
      skipped + metres + busiest(choices)
    end

    # The busiest circuit's share of its 80 % limit, from 0 to 1: the final tie-break.
    def busiest(choices)
      load = display.circuits.transform_values(&:load)
      @order.each_with_index do |l, k|
        load[choices[k].outlet.circuit] += l.watts if choices[k]
      end
      load.map { |id, w| w / display.circuit_watts(display.circuits[id]) }.max.clamp(0, 1)
    end

    # Does an arrangement keep every rule? Public for the tests.
    def safe?(choices)
      circuit = display.circuits.transform_values(&:load)
      outlet = Hash.new(0.0)
      cords = []
      @order.each_with_index do |l, k|
        o = choices[k]
        next unless o
        return false unless @options[l.id].include?(o)

        circuit[o.outlet.circuit] += l.watts
        outlet[o.outlet.id] += l.watts
        cords << o.cord.index if o.cord
      end
      return false if cords.uniq.size != cords.size
      return false if outlet.any? { |_, w| w > display.outlet_watts + 1e-9 }

      circuit.all? { |id, w| w <= display.circuit_watts(display.circuits[id]) + 1e-9 || w <= display.circuits[id].load + 1e-9 }
    end

    attr_reader :order

    private

    def build_options(light)
      amps = light.watts / display.voltage
      list = []
      why = []
      display.outlets.each_value do |o|
        if light.outside && !o.rcd
          why << :rcd
          next
        end
        reach = Planner.reach(light, o)
        if reach <= PLUG_REACH
          list << Option.new(outlet: o, cord: nil, reach: reach, drop: 0.0)
          next
        end
        display.cords.each do |c|
          next why << :short if c.length < reach
          next why << :rating if c.amps < amps

          drop = amps * c.resistance / display.voltage
          next why << :drop if drop > MAX_DROP

          list << Option.new(outlet: o, cord: c, reach: reach, drop: drop)
        end
      end
      # Shortest first, so the search finds good plans early and prunes more.
      @options[light.id] = list.sort_by { |opt| [opt.metres, opt.outlet.id, opt.cord&.index || -1] }
      @reasons[light.id] = explain(why, light, amps) if list.empty?
    end

    def explain(why, light, amps)
      return 'no outlet has an RCD (GFCI), which outdoor lights need' if why.all?(:rcd)
      return 'no cord is long enough to reach it from an outlet with an RCD (GFCI)' if why.include?(:short) && !why.intersect?(%i[rating drop])
      return format('it draws %.1f A, more than any long-enough cord is rated for', amps) if why.include?(:rating) && !why.include?(:drop)

      'every cord long enough to reach it would drop more than 3 % of the voltage'
    end

    STOCK = [5, 10, 15, 20, 25, 30, 40, 50].freeze

    # Why a light that could have had a cord was left off, and what would fix it: usually every
    # cord that reaches it is in use, so name the shortest extra cord that would power it.
    def remedy(light, choice)
      circuit = display.circuits.transform_values(&:load)
      outlet = Hash.new(0.0)
      choice.each do |id, o|
        circuit[o.outlet.circuit] += display.lights[id].watts
        outlet[o.outlet.id] += display.lights[id].watts
      end
      amps = light.watts / display.voltage
      best = nil
      display.outlets.each_value do |o|
        next if light.outside && !o.rcd
        next if circuit[o.circuit] + light.watts > display.circuit_watts(display.circuits[o.circuit])
        next if outlet[o.id] + light.watts > display.outlet_watts

        reach = Planner.reach(light, o)
        length = STOCK.find { |len| len >= reach }
        next unless length

        rating = [10, 15, 20].find { |a| a >= amps && amps * Cord.new(length: length, amps: a).resistance / display.voltage <= MAX_DROP }
        best = [length, rating, o.id] if rating && (best.nil? || length < best[0])
      end
      return 'no circuit or socket within reach has enough spare capacity for it' unless best

      format('every cord that reaches it is already in use; one more %d m cord (%d A) would power it from outlet %s', *best)
    end

    # floors[k]: the least the lights from k onwards could possibly add (their shortest option).
    def suffix_floors(lights)
      floors = Array.new(lights.size + 1, 0.0)
      (lights.size - 1).downto(0) do |k|
        l = lights[k]
        cheapest = @options[l.id].map(&:metres).min || (SKIP + 10 * l.watts)
        floors[k] = floors[k + 1] + [cheapest, SKIP + 10 * l.watts].min
      end
      floors
    end

    def search(k, cost, chosen)
      @nodes += 1
      return if @nodes > NODE_LIMIT
      return if cost + @floor[k] >= @best_cost

      if k == @order.size
        total = cost + busiest(chosen)
        if total < @best_cost - 1e-9
          @best_cost = total
          @best = chosen.dup
        end
        return
      end
      light = @order[k]
      @options[light.id].each do |o|
        next if o.cord && @used[o.cord.index] == 1
        # Identical cords are interchangeable: always take the lowest-numbered free one.
        next if o.cord && @twins[o.cord.index].any? { |t| @used[t].zero? }

        c = o.outlet.circuit
        next if @circuit_load[c] + light.watts > display.circuit_watts(display.circuits[c]) + 1e-9
        next if @outlet_load[o.outlet.id] + light.watts > display.outlet_watts + 1e-9

        @circuit_load[c] += light.watts
        @outlet_load[o.outlet.id] += light.watts
        @used |= (1 << o.cord.index) if o.cord
        chosen.push(o)
        search(k + 1, cost + o.metres, chosen)
        chosen.pop
        @used &= ~(1 << o.cord.index) if o.cord
        @outlet_load[o.outlet.id] -= light.watts
        @circuit_load[c] -= light.watts
      end
      # Or leave this light off (only ever chosen when nothing else works out).
      chosen.push(nil)
      search(k + 1, cost + SKIP + 10 * light.watts, chosen)
      chosen.pop
    end
  end
end
