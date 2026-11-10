# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/tinselwatt'

BIN = File.expand_path('../bin/tinselwatt', __dir__)
EXAMPLES = File.expand_path('../examples', __dir__)

def display(text)
  Tinselwatt::Display.parse(text)
end

BASE = <<~D
  voltage 230
  circuit a breaker 10
  outlet porch circuit a at 0 0 rcd
D

class TestReading < Minitest::Test
  def test_reads_the_example
    d = display(File.read(File.join(EXAMPLES, 'front-yard.txt')))
    assert_equal "The Nguyens' front yard", d.title
    assert_equal 3, d.circuits.size
    assert_equal 9, d.lights.size
    assert_equal 7, d.cords.size
    refute d.outlets['lounge'].rcd
    refute d.lights['window-candles'].outside
    assert_equal 1840, d.circuit_watts(d.circuits['c2'])
  end

  def test_bad_files_are_refused_without_repeating_them
    bad = {
      "#{BASE}light x watts 50 at 1 1\nbanana 3" => /line 5: unknown line/,
      "#{BASE}voltage 110" => /given twice/,
      "voltage 110\n#{BASE}" => /230 or 120/,
      "#{BASE}light x watts lots at 1 1" => /watts must be a number/,
      "#{BASE}light x watts 50 at 1" => /at needs two numbers/,
      "#{BASE}light x watts 50 at 1 1 colour red" => /unexpected word/,
      "#{BASE}light X watts 50 at 1 1" => /lowercase/,
      "#{BASE}light x watts 50 at 1 1\nlight x watts 5 at 2 2" => /already defined/,
      "#{BASE}light x watts 50 at 1 1\noutlet o circuit nope at 1 1" => /isn't defined/,
      "#{BASE}light x watts 300 at 1 1 chain-limit 216" => /two ends/,
      "#{BASE}light x watts 50 at 1 1\ncord 500 rated 10" => /between 1 and 50/,
      "#{BASE}light x watts 50 at 1 1\ncord 10 rated 10 count 40" => /between 1 and 10/,
      "#{BASE}light x watts 50 at 1 1\ntitle: <script>" => /title is/,
      "#{BASE}light x watts 50 at 1 1\ntitle: a\u0007b" => /control/,
      "#{BASE}light x watts 50 at 1 1\ntitle: abc\u202Edef" => /invisible/,
      BASE => /at least one circuit, outlet and light/,
      'x' * 40_000 => /larger than 32 KB/,
      "#{BASE}light x watts 50 at 1 1\n\xFF\xFE".dup.force_encoding('BINARY') => /UTF-8/,
      "#{BASE}#{(1..25).map { |i| "light l#{i} watts 5 at 1 1\n" }.join}" => /at most 24 lights/
    }
    bad.each do |text, re|
      err = assert_raises(Tinselwatt::InputError, re.inspect) { display(text) }
      assert_match re, err.message
      refute_match(/script|banana|lots/, err.message)
    end
  end
end

class TestRules < Minitest::Test
  def test_outdoor_lights_need_an_rcd
    d = display("voltage 230\ncircuit a breaker 10\noutlet o circuit a at 0 0\nlight x watts 50 at 0 0\ncord 10 rated 10")
    plan = Tinselwatt::Planner.new(d).plan
    assert_match(/RCD/, plan.skipped['x'])
    inside = display("voltage 230\ncircuit a breaker 10\noutlet o circuit a at 0 0\nlight x watts 50 at 0 0 inside")
    assert_empty Tinselwatt::Planner.new(inside).plan.skipped
  end

  def test_a_heavy_load_on_a_long_thin_cord_drops_too_much_voltage
    # 1,000 W at 120 V is 8.3 A; 50 m of 1.31 mm² cord is 1.3 Ω there and back: an 9 % drop.
    d = display("voltage 120\ncircuit a breaker 20\noutlet o circuit a at 0 0 rcd\nlight x watts 1000 at 40 0\ncord 50 rated 13")
    plan = Tinselwatt::Planner.new(d).plan
    assert_match(/3 % of the voltage/, plan.skipped['x'])
  end

  def test_cords_must_reach_and_carry_the_current
    short = display("#{BASE}light x watts 50 at 20 0\ncord 10 rated 10")
    assert_match(/long enough/, Tinselwatt::Planner.new(short).plan.skipped['x'])
    weak = display("voltage 120\ncircuit a breaker 20\noutlet o circuit a at 0 0 rcd\nlight x watts 1500 at 5 0\ncord 10 rated 10")
    assert_match(/12\.5 A/, Tinselwatt::Planner.new(weak).plan.skipped['x'])
  end

  def test_a_circuit_never_goes_past_eighty_percent
    # 10 A at 230 V is 2,300 W; 80 % is 1,840 W; 1,500 W is already on it.
    d = display("voltage 230\ncircuit a breaker 10 load 1500\noutlet o circuit a at 0 0 rcd\n" \
                "light big watts 300 at 0 0\nlight small watts 40 at 0 0\nlight more watts 30 at 0 0")
    plan = Tinselwatt::Planner.new(d).plan
    lit = plan.choice.keys.sum { |id| d.lights[id].watts }
    assert_operator 1500 + lit, :<=, 1840
    assert_equal %w[big small], plan.choice.keys.sort, 'it keeps the most watts it can'
    assert_match(/spare capacity/, plan.skipped['more'])
  end

  def test_suggests_the_extra_cord_that_would_help
    plan = Tinselwatt::Planner.new(display(File.read(File.join(EXAMPLES, 'front-yard.txt')))).plan
    assert_equal %w[path-stakes projector], plan.skipped.keys.sort
    assert_match(/one more 5 m cord \(10 A\) would power it from outlet porch/, plan.skipped['path-stakes'])
  end
end

class TestSearch < Minitest::Test
  # Every arrangement, the slow way: each light to every option or left off.
  def brute(planner)
    best = Float::INFINITY
    walk = lambda do |k, chosen|
      if k == planner.order.size
        best = [best, planner.cost_of(chosen)].min if planner.safe?(chosen)
        return
      end
      (planner.options[planner.order[k].id] + [nil]).each do |o|
        chosen.push(o)
        walk.call(k + 1, chosen)
        chosen.pop
      end
    end
    walk.call(0, [])
    best
  end

  def random_display(rng)
    v = rng.rand < 0.5 ? 230 : 120
    lines = ["voltage #{v}"]
    circuits = (1..rng.rand(1..3)).map { |i| "c#{i}" }
    circuits.each { |c| lines << "circuit #{c} breaker #{[10, 15, 16, 20].sample(random: rng)} load #{rng.rand(0..1500)}" }
    rng.rand(1..3).times { |i| lines << "outlet o#{i} circuit #{circuits.sample(random: rng)} at #{rng.rand(0..20)} #{rng.rand(0..20)}#{rng.rand < 0.75 ? ' rcd' : ''}" }
    rng.rand(2..5).times { |i| lines << "light l#{i} watts #{rng.rand(20..900)} at #{rng.rand(0..25)} #{rng.rand(0..25)}#{rng.rand < 0.2 ? ' inside' : ''}" }
    rng.rand(1..4).times { lines << "cord #{[5, 10, 15, 20, 30].sample(random: rng)} rated #{[10, 13, 15].sample(random: rng)}" }
    display(lines.join("\n"))
  end

  def test_branch_and_bound_finds_the_best_arrangement
    rng = Random.new(7)
    120.times do |t|
      d = random_display(rng)
      planner = Tinselwatt::Planner.new(d)
      plan = planner.plan
      chosen = planner.order.map { |l| plan.choice[l.id] }
      assert planner.safe?(chosen), "display #{t}: the plan breaks a rule"
      assert plan.proven
      assert_in_delta brute(planner), planner.cost_of(chosen), 1e-6, "display #{t}"
    end
  end

  def test_identical_cords_are_not_tried_twice
    lines = ["voltage 230\ncircuit a breaker 16\noutlet o circuit a at 0 0 rcd"]
    12.times { |i| lines << "light l#{i} watts 40 at #{i + 3} 0" }
    lines << 'cord 20 rated 10 count 10'
    plan = Tinselwatt::Planner.new(display(lines.join("\n"))).plan
    assert plan.proven
    assert_operator plan.nodes, :<, 50_000
    assert_equal 2, plan.skipped.size
  end
end

class TestCommandLine < Minitest::Test
  def run_bin(*args)
    Open3.capture3(RbConfig.ruby, BIN, *args)
  end

  def test_examples
    out, _err, status = run_bin(File.join(EXAMPLES, 'porch-120v.txt'))
    assert_equal 0, status.exitstatus
    assert_match(/Tinselwatt: Maple Street porch \(120 V\)/, out)
    assert_match(/Best possible arrangement/, out)
    _out, _err, status = run_bin(File.join(EXAMPLES, 'front-yard.txt'))
    assert_equal 3, status.exitstatus, 'exit 3 when lights are left off'
  end

  def test_bad_input
    Dir.mktmpdir do |dir|
      secret = File.join(dir, 'secret.txt')
      File.write(secret, "password hunter2\n")
      big = File.join(dir, 'big.txt')
      File.write(big, 'x' * 40_000)
      link = File.join(dir, 'link.txt')
      File.symlink(File.join(EXAMPLES, 'front-yard.txt'), link)
      [[secret], [big], [link], [dir], [File.join(dir, 'missing.txt')]].each do |args|
        out, err, status = run_bin(*args)
        assert_equal 1, status.exitstatus, args.inspect
        assert_empty out
        refute_match(/hunter2/, err)
      end
      _out, _err, status = run_bin
      assert_equal 2, status.exitstatus
    end
  end
end
