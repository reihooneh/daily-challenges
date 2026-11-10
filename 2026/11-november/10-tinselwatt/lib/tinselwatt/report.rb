# frozen_string_literal: true

module Tinselwatt
  # Writes a plan as a plug-in sheet: outlet by outlet, then each circuit's load and what's spare.
  module Report
    module_function

    def watts(w)
      w.round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse + ' W'
    end

    def text(plan)
      d = plan.display
      out = +"Tinselwatt: #{d.title} (#{d.voltage} V)\n\n"
      by_outlet = Hash.new { |h, k| h[k] = [] }
      plan.choice.each { |id, opt| by_outlet[opt.outlet.id] << [d.lights[id], opt] }
      d.outlets.each_value do |o|
        rows = by_outlet[o.id]
        next if rows.empty?

        total = rows.sum { |l, _| l.watts }
        out << "Outlet #{o.id} (circuit #{o.circuit}#{o.rcd ? ', RCD' : ''}): #{watts(total)} of #{watts(d.outlet_watts)}\n"
        rows.sort_by { |l, _| l.id }.each do |l, opt|
          how = opt.cord ? format('%g m cord (%g A), %.1f m run, %.1f%% voltage drop', opt.cord.length, opt.cord.amps, opt.reach, 100 * opt.drop) : 'plugs straight in'
          out << format("  %-22s %8s   %s\n", l.id, watts(l.watts), how)
        end
        out << "\n"
      end
      out << "Circuits (80% of the breaker, for loads left on for hours):\n"
      load = d.circuits.transform_values(&:load)
      plan.choice.each { |id, opt| load[opt.outlet.circuit] += d.lights[id].watts }
      d.circuits.each_value do |c|
        limit = d.circuit_watts(c)
        lights = load[c.id] - c.load
        out << format("  %-12s %4g A breaker: %s already on + %s of lights = %s of %s (%d%%)\n",
                      c.id, c.breaker, watts(c.load), watts(lights), watts(load[c.id]), watts(limit), (100.0 * load[c.id] / limit).round)
      end
      used = plan.choice.values.filter_map(&:cord).map(&:index)
      spare = d.cords.reject { |c| used.include?(c.index) }
      out << "\nCord laid: #{plan.metres.round(1)} m. "
      out << (spare.empty? ? "No cords spare.\n" : "Spare: #{spare.map { |c| format('%g m (%g A)', c.length, c.amps) }.join(', ')}.\n")
      unless plan.skipped.empty?
        out << "\nLeft off:\n"
        plan.skipped.each { |id, why| out << "  #{id} (#{watts(d.lights[id].watts)}): #{why}\n" }
      end
      out << (plan.proven ? "Best possible arrangement (#{plan.nodes} steps searched).\n" : "Best found within the search limit; it may not be the very best.\n")
      out
    end
  end
end
