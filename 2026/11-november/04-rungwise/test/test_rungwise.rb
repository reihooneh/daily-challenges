# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/rungwise'

EXAMPLE = File.expand_path('../examples/car.txt', __dir__)
BIN = File.expand_path('../bin/rungwise', __dir__)

def policy_text(extra = '', years: 3, ladder: nil)
  ladder ||= <<~L
    level Bottom discount 0% claim-to Bottom
    level Middle discount 30% claim-to Bottom
    level Top discount 60% claim-to Bottom
  L
  <<~P
    premium 1000
    excess 500
    accident-chance 10%
    repair-median 2000
    repair-spread 0.8
    years #{years}
    #{extra}
    #{ladder}
  P
end

class TestRepairs < Minitest::Test
  def test_capped_mean_matches_numerical_integration
    r = Rungwise::Repairs.new(2000, 0.8)
    [100, 800, 2000, 6000, 40_000].each do |t|
      # E[min(D, t)] = integral of P(D > x) from 0 to t (trapezoids on a log grid would do; a fine
      # linear grid is plenty here).
      steps = 20_000
      h = t.to_f / steps
      sum = (0..steps).sum { |i| (i.zero? || i == steps ? 0.5 : 1) * r.prob_above(i * h) }
      assert_in_delta sum * h, r.capped_mean(t), t * 1e-4
    end
    assert_in_delta r.mean, r.capped_mean(Float::INFINITY), 1e-9
    assert_in_delta 0.5, r.prob_above(2000), 1e-12
  end

  def test_samples_have_the_right_median
    r = Rungwise::Repairs.new(3000, 0.9)
    rng = Random.new(3)
    s = Array.new(20_001) { r.sample(rng) }.sort
    assert_in_delta 3000, s[10_000], 150
  end
end

class TestModel < Minitest::Test
  def model(text = policy_text, **kw) = Rungwise::Model.new(Rungwise::Parser.parse(text), **kw)

  def test_the_last_year_threshold_is_the_excess
    m = model
    m.levels.each_index { |l| assert_in_delta 500, m.threshold[1][l], 1e-9 }
  end

  def test_threshold_is_where_claiming_and_paying_cost_the_same
    m = model(policy_text(years: 4))
    after = m.value[3]
    m.levels.each_index do |l|
      t = m.threshold[4][l]
      pay = ->(d) { d + m.beta * after[m.up(l)] }
      claim = ->(_d) { 500 + m.beta * after[m.down(l)] }
      assert_operator pay.call(t * 0.99), :<=, claim.call(t * 0.99) + 1e-9
      assert_operator pay.call(t * 1.01), :>=, claim.call(t * 1.01) - 1e-9 unless t <= 500
    end
  end

  def test_the_best_rule_beats_every_other_rule
    rng = Random.new(11)
    40.times do
      text = policy_text("interest #{rng.rand(0..8)}%", years: rng.rand(1..6))
      m = model(text)
      best = m.best_cost
      assert_in_delta best, m.cost_of_rule { |l, t| m.threshold[t][l] }, 1e-6
      8.times do
        table = Hash.new { |h, k| h[k] = 500 + rng.rand * 5000 }
        other = m.cost_of_rule { |l, t| table[[l, t]] }
        assert_operator best, :<=, other + 1e-9
      end
      assert_operator best, :<=, m.cost_of_rule { 500 } + 1e-9
      assert_operator best, :<=, m.cost_of_rule { Float::INFINITY } + 1e-9
    end
  end

  def test_simulation_agrees_with_the_exact_answer
    m = model(File.read(EXAMPLE))
    sim = m.simulate(60_000, Random.new(5))
    assert_in_delta m.best_cost, sim, m.best_cost * 0.02
  end

  def test_protection_never_costs_more_before_its_price
    m = model(policy_text(years: 5))
    prot = model(policy_text(years: 5), protected: true)
    assert_operator prot.best_cost, :<=, m.best_cost + 1e-9
  end

  def test_no_bonus_to_lose_means_claim_anything_over_the_excess
    flat = <<~L
      level Only discount 20% claim-to Only
      level Same discount 20% claim-to Only
    L
    m = model(policy_text(years: 4, ladder: flat))
    (1..4).each { |t| m.levels.each_index { |l| assert_in_delta 500, m.threshold[t][l], 1e-6 } }
  end
end

class TestParser < Minitest::Test
  def rejects(text, fragment)
    err = assert_raises(Rungwise::PolicyError) { Rungwise::Parser.parse(text) }
    assert_includes err.message, fragment
    refute_match(/SECRET|<script>/, err.message)
  end

  def test_reads_the_example
    p = Rungwise::Parser.parse(File.read(EXAMPLE))
    assert_equal 6, p.levels.size
    assert_equal 2, p.start
    assert_in_delta 0.09, p.chance, 1e-12
    assert_equal 1, p.levels[3].after_claim
  end

  def test_friendly_input
    p = Rungwise::Parser.parse("\uFEFF" + policy_text.gsub("\n", "\r\n").sub('premium 1000', 'premium $1,000'))
    assert_in_delta 1000, p.premium, 1e-9
  end

  def test_refuses_bad_policies
    rejects('', 'at least two levels')
    rejects(policy_text.sub('premium 1000', ''), "needs a 'premium' line")
    rejects(policy_text.sub('premium 1000', 'premium lots'), 'must be a number')
    rejects(policy_text.sub('premium 1000', 'premium 50%'), 'not a percentage')
    rejects(policy_text.sub('accident-chance 10%', 'accident-chance 95%'), 'from 0 to 0.9')
    rejects(policy_text.sub('years 3', 'years 2.5'), 'whole number')
    rejects(policy_text.sub('years 3', 'years 99'), 'from 1 to 30')
    rejects(policy_text.sub('claim-to Bottom', 'claim-to Nowhere'), 'not listed')
    rejects(policy_text.sub('level Middle discount 30% claim-to Bottom', 'level Middle discount 30% claim-to Top'), 'only keep you where you are or move you down')
    rejects(policy_text.sub('level Top', 'level Middle'), 'same name')
    rejects(policy_text + "start Nowhere\n", 'starting level is not listed')
    rejects(policy_text + "level <script> discount 1% claim-to Bottom\n", 'level name')
    rejects(policy_text + "policy Car\u202eSECRET\n", 'invisible')
    rejects(policy_text + "policy Car\e[2J\n", 'control')
    rejects(policy_text + "premium 5\n", 'comes once')
    rejects(policy_text + "rm -rf SECRET\n", 'lines start with')
    rejects(policy_text + "# #{'x' * 300}\n", 'longer than 200')
    rejects('#' * 40_000, 'larger than 32 KB')
    rejects((+"premium 1\n").force_encoding('UTF-8') + "\xff".dup.force_encoding('UTF-8'), 'UTF-8')
    many = (1..31).map { |i| "level L#{i} discount 1% claim-to L1\n" }.join
    rejects(policy_text(ladder: many), 'at most 30 levels')
  end
end

class TestCommandLine < Minitest::Test
  def run_cli(*args, input: '')
    Open3.capture3(RbConfig.ruby, '-w', BIN, *args, stdin_data: input)
  end

  def test_exit_codes_and_files
    out, err, st = run_cli(EXAMPLE)
    assert_equal 0, st.exitstatus, err
    assert_includes out, 'This year: if you have an at-fault accident, claim only if the repair costs more than $2,540.'
    assert_includes out, 'Bonus protection at $95 a year'
    assert_empty err, 'no warnings under ruby -w'
    assert_equal out, run_cli('-', input: File.read(EXAMPLE))[0]
    assert_equal 2, run_cli.last.exitstatus
    assert_equal 2, run_cli('a', 'b').last.exitstatus
    Dir.mktmpdir do |dir|
      _o, e, st = run_cli(dir)
      assert_equal 2, st.exitstatus
      assert_includes e, 'not a regular file'
      link = File.join(dir, 'link.txt')
      File.symlink(EXAMPLE, link)
      _o, e, st = run_cli(link)
      assert_equal 2, st.exitstatus
      assert_includes e, 'symbolic link'
    end
    _o, e, = run_cli('secret-name-zz.txt')
    refute_includes e, 'secret-name'
    _o, e, = run_cli('-', input: '#' * 100_000)
    assert_includes e, 'larger than 32 KB'
  end
end
