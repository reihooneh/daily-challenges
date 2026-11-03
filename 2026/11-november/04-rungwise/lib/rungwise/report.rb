# frozen_string_literal: true

module Rungwise
  # The printed advice.
  module Report
    module_function

    def money(v)
      return 'never' if v == Float::INFINITY

      "$#{v.round.to_s.reverse.scan(/\d{1,3}/).join(',').reverse}"
    end

    def pct(v) = "#{(v * 100).round}%"

    def render(policy)
      m = Model.new(policy)
      r = m.repairs
      lo = Math.exp(r.mu - 0.6745 * r.sigma)
      hi = Math.exp(r.mu + 0.6745 * r.sigma)
      out = []
      out << "RUNGWISE  #{policy.title}"
      out << "Base premium #{money(policy.premium)} a year, excess #{money(policy.excess)}, at-fault accident chance #{pct(policy.chance)} a year."
      out << "Repair bills: typically #{money(policy.median)}; half fall between #{money(lo)} and #{money(hi)}."
      out << "Planning #{policy.years} year#{policy.years == 1 ? '' : 's'} ahead from #{policy.levels[policy.start].name}" \
             "#{policy.interest.positive? ? ", with money later discounted at #{pct(policy.interest)} a year" : ''}."
      out << ''

      years = [policy.years, 6].min
      cols = policy.years.downto(policy.years - years + 1).to_a
      width = [policy.levels.map { |l| l.name.length + 7 }.max, 18].max
      out << 'Claim an accident only if the repair bill is more than:'
      out << format("  %-#{width}s", 'Level (discount)') + cols.map { |t| format('%11s', t == 1 ? '1 yr left' : "#{t} yrs left") }.join
      policy.levels.each_with_index.reverse_each do |lvl, l|
        label = "#{lvl.name} (#{pct(lvl.discount)})"
        mark = l == policy.start ? '>' : ' '
        out << format("#{mark} %-#{width}s", label) + cols.map { |t| format('%11s', money(m.threshold[t][l])) }.join
      end
      out << "  ('>' is where you start. A smaller bill is cheaper to pay yourself than the lost discount.)"
      out << ''

      best = m.best_cost
      always = m.cost_of_rule { policy.excess }
      never = m.cost_of_rule { Float::INFINITY }
      out << "Expected cost of the next #{policy.years} years (premiums, excesses and bills you pay yourself):"
      out << format('  %-34s %10s', 'Claim only above the thresholds', money(best))
      out << format('  %-34s %10s  (%s more)', 'Claim every bill over the excess', money(always), money(always - best))
      out << format('  %-34s %10s  (%s more)', 'Never claim', money(never), money(never - best))
      t_now = m.threshold[policy.years][policy.start]
      out << ''
      out << "This year: if you have an at-fault accident, claim only if the repair costs more than #{money(t_now)}."

      if policy.protection
        prot = Model.new(policy, protected: true)
        with = prot.best_cost + policy.protection * (0...policy.years).sum { |k| (1 / (1 + policy.interest))**k }
        verdict = with < best ? "worth it: it saves about #{money(best - with)}" : "not worth it: it costs about #{money(with - best)} more than it saves"
        out << "Bonus protection at #{money(policy.protection)} a year (claims don't move you down): #{verdict}."
      end
      "#{out.join("\n")}\n"
    end
  end
end
