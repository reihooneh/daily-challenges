# frozen_string_literal: true

module Rungwise
  # Repair bills follow a log-normal distribution: most are modest, a few are huge. The median and
  # the spread (the standard deviation of the log) describe it.
  class Repairs
    attr_reader :mu, :sigma

    def initialize(median, spread)
      @mu = Math.log(median)
      @sigma = spread
    end

    def self.phi(x)
      0.5 * (1 + Math.erf(x / Math.sqrt(2)))
    end

    def mean
      Math.exp(@mu + (@sigma**2) / 2)
    end

    def prob_above(t)
      return 1.0 if t <= 0

      1 - Repairs.phi((Math.log(t) - @mu) / @sigma)
    end

    # E[min(D, t)]: the bill if you pay it yourself, capped at t, in closed form.
    def capped_mean(t)
      return 0.0 if t <= 0
      return mean if t == Float::INFINITY

      below = mean * Repairs.phi((Math.log(t) - @mu - @sigma**2) / @sigma)
      below + t * prob_above(t)
    end

    # One random bill, for simulations (Box-Muller).
    def sample(rng)
      u1 = 1 - rng.rand
      u2 = rng.rand
      Math.exp(@mu + @sigma * Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2))
    end
  end

  # The decision, year by year, as a Markov decision process solved backwards (dynamic programming).
  #
  # value[t][l] is the expected cost of the next t years starting the year on level l, choosing
  # well. Each year you pay the premium for your level. With chance p you have an at-fault
  # accident with repair bill D, and you choose:
  #   pay it yourself: cost D,          next year one rung up
  #   claim it:        cost the excess, next year on the claim's level
  # So you should claim exactly when D > excess + (cost of the claim's level - cost of the rung up),
  # the threshold. With no accident, you go one rung up.
  class Model
    attr_reader :policy, :repairs, :value, :threshold

    def initialize(policy, protected: false)
      @policy = policy
      @protected = protected
      @repairs = Repairs.new(policy.median, policy.spread)
      solve
    end

    def levels = @policy.levels
    def up(level) = [level + 1, levels.size - 1].min
    def down(level) = @protected ? level : levels[level].after_claim
    def premium(level) = @policy.premium * (1 - levels[level].discount)
    def beta = 1 / (1 + @policy.interest)

    # Expected cost of one year on `level` given the future costs `after` and a claim threshold.
    def year_cost(level, after, threshold)
      stay_up = beta * after[up(level)]
      claimed = beta * after[down(level)]
      p = @policy.chance
      # With an accident: pay min(D, threshold) yourself, and either way the future is stay_up,
      # except when you claim (D > threshold), which costs excess + claimed instead of D + stay_up.
      t = [threshold, @policy.excess].max
      accident = if t == Float::INFINITY
                   @repairs.mean + stay_up
                 else
                   @repairs.capped_mean(t) - t * @repairs.prob_above(t) +
                     @repairs.prob_above(t) * (@policy.excess + claimed) + (1 - @repairs.prob_above(t)) * stay_up
                 end
      premium(level) + (1 - p) * stay_up + p * accident
    end

    # Solves for every level and every number of years left.
    def solve
      n = levels.size
      @value = [Array.new(n, 0.0)]
      @threshold = [Array.new(n, Float::INFINITY)]
      (1..@policy.years).each do |t|
        after = @value[t - 1]
        th = Array.new(n) { |l| [@policy.excess + beta * (after[down(l)] - after[up(l)]), @policy.excess].max }
        @threshold << th
        @value << Array.new(n) { |l| year_cost(l, after, th[l]) }
      end
    end

    # Expected cost of a fixed rule: claim whenever the bill is over `rule.call(level, years_left)`.
    def cost_of_rule(years = @policy.years, start = @policy.start)
      after = Array.new(levels.size, 0.0)
      (1..years).each do |t|
        after = Array.new(levels.size) { |l| year_cost(l, after, yield(l, t)) }
      end
      after[start]
    end

    def best_cost(years = @policy.years, start = @policy.start) = @value[years][start]

    # Simulates many drivers following the best rule, for checking the arithmetic.
    def simulate(runs, rng)
      total = 0.0
      runs.times do
        level = @policy.start
        @policy.years.downto(1) do |left|
          years_done = @policy.years - left
          cost = premium(level)
          if rng.rand < @policy.chance
            bill = @repairs.sample(rng)
            if bill > @threshold[left][level]
              cost += [bill, @policy.excess].min
              level = down(level)
            else
              cost += bill
              level = up(level)
            end
          else
            level = up(level)
          end
          total += cost * (beta**years_done)
        end
      end
      total / runs
    end
  end
end
