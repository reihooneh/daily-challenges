# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/crosscue'

class TestAssignment < Minitest::Test
  def brute(cost, allowed)
    n = cost.size
    (0...n).to_a.permutation.select { |p| p.each_with_index.all? { |j, i| allowed[i][j] } }
  end

  def test_matches_brute_force_on_random_cases
    rng = Random.new(7)
    60.times do
      n = rng.rand(2..6)
      cost = Array.new(n) { Array.new(n) { (rng.rand * 10).round(2) } }
      allowed = Array.new(n) { Array.new(n, true) }
      # Pin one row to one column now and then, like a dancer who must take a given spot.
      if rng.rand < 0.5
        r = rng.rand(n)
        c = rng.rand(n)
        n.times { |j| allowed[r][j] = (j == c) }
        n.times { |i| allowed[i][c] = (i == r) }
      end
      perms = brute(cost, allowed)
      best_max = perms.map { |p| p.each_with_index.map { |j, i| cost[i][j] }.max }.min
      best_total = perms.select { |p| p.each_with_index.map { |j, i| cost[i][j] }.max <= best_max + 1e-12 }
                        .map { |p| p.each_with_index.sum { |j, i| cost[i][j] } }.min
      got = Crosscue::Assignment.plan(cost, allowed)
      assert_in_delta best_max, got[:longest], 1e-9, 'smallest possible longest walk'
      assert_in_delta best_total, got[:total], 1e-9, 'least total walking among those'
      got[:assignment].each_with_index { |j, i| assert allowed[i][j], 'pins respected' }
      assert_equal (0...n).to_a, got[:assignment].sort, 'each spot used once'
    end
  end

  def test_hungarian_alone_minimises_the_total
    cost = [[4, 1, 3], [2, 0, 5], [3, 2, 2]]
    a = Crosscue::Assignment.hungarian(cost)
    assert_equal 5, a.each_with_index.sum { |j, i| cost[i][j] }
  end

  def test_impossible_pins_are_reported
    assert_raises(ArgumentError) { Crosscue::Assignment.plan([[1, 2], [3, 4]], [[false, false], [true, true]]) }
  end
end

class TestPaths < Minitest::Test
  def move(name, from, to, start = 0.0, finish = 8.0)
    Crosscue::Move.new(dancer: name, from: from, to: to, start: start, finish: finish)
  end

  def test_closest_approach_matches_fine_sampling
    rng = Random.new(3)
    100.times do
      a = move('A', [rng.rand * 8, rng.rand * 8], [rng.rand * 8, rng.rand * 8], rng.rand(0..3).to_f, rng.rand(5..8).to_f)
      b = move('B', [rng.rand * 8, rng.rand * 8], [rng.rand * 8, rng.rand * 8], rng.rand(0..3).to_f, rng.rand(5..8).to_f)
      exact, = Crosscue::Paths.closest(a, b, 8)
      sampled = (0..8000).map { |k| t = k / 1000.0; Math.hypot(*Crosscue::Paths.diff(a.at(t), b.at(t))) }.min
      assert_operator exact, :<=, sampled + 1e-9
      assert_in_delta sampled, exact, 1e-3
    end
  end

  def test_crossing_dancers_are_flagged_and_partners_are_not
    crossing = [move('A', [0, 0], [4, 4]), move('B', [4, 0], [0, 4])]
    found = Crosscue::Paths.conflicts(crossing, 8, 0.6)
    assert_equal 1, found.size
    assert_in_delta 0, found.first[:distance], 1e-9
    partners = [move('A', [0, 0], [4, 0]), move('B', [0, 0.3], [4, 0.3])]
    assert_empty Crosscue::Paths.conflicts(partners, 8, 0.6), 'side by side all the way is fine'
  end

  def test_retiming_clears_a_near_miss_within_pace
    moves = [move('A', [0, 2], [4, 2]), move('B', [2, 0], [2, 4])]
    needed = ->(m) { (m / 1.4 / 0.5).ceil }
    left = Crosscue::Paths.stagger!(moves, 8, 0.6, needed)
    assert_empty left
    moves.each { |m| assert_operator m.finish - m.start, :>=, needed.call(m.distance) }
  end
end

class TestParser < Minitest::Test
  BASE = <<~SHOW
    show Test
    stage 10 x 8
    formation Start
      Ava 1 1
      Ben 2 2
    formation End in 4 counts
      spot 3 3
      Ben 4 4
  SHOW

  def bad(text, fragment)
    err = assert_raises(Crosscue::ShowError) { Crosscue::Parser.parse(text) }
    assert_includes err.message, fragment
  end

  def test_reads_a_show
    s = Crosscue::Parser.parse(BASE)
    assert_equal %w[Ava Ben], s.dancers
    assert_equal 4, s.formations[1].counts
    assert_equal({ 'Ben' => [4.0, 4.0] }, s.formations[1].pins)
    assert_in_delta 0.5, s.beat
  end

  def test_refuses_bad_shows
    bad(BASE.sub("stage 10 x 8\n", ''), 'stage WIDTH x DEPTH')
    bad(BASE.sub('spot 3 3', 'spot 3 3\n  spot 5 5'.gsub('\n', "\n")), '3 places for 2 dancers')
    bad(BASE.sub('spot 3 3', 'spot 30 3'), 'off the stage')
    bad(BASE.sub('Ben 4 4', 'Zed 4 4'), "Zed isn't in the first formation")
    bad(BASE.sub('Ben 2 2', 'Ava 2 2'), 'placed twice')
    bad(BASE.sub('formation Start', 'formation Start in 4 counts'), 'takes no counts')
    bad(BASE.sub('End in 4 counts', 'End'), 'say how long the change takes')
    bad(BASE.sub('in 4 counts', 'in 99 counts'), '1 to 64 counts')
    bad(BASE.sub('stage 10 x 8', 'stage 1e3 x 8'), 'plain number')
    bad(BASE.sub('stage 10 x 8', 'stage 100 x 8'), 'between 2 and 60')
    bad(BASE.sub('Ava 1 1', '<b>Ava 1 1'), 'dancer names')
    bad(BASE.sub('show Test', "show Te\e[2Jst"), 'control or hidden')
    bad(BASE.sub('show Test', "show Te‮st"), 'control or hidden')
    bad(BASE + ('#' * 300), 'longer than')
    bad('#' * 70_000, 'larger than 64 KB')
    bad("show T\xff\n".dup.force_encoding('UTF-8'), 'not valid UTF-8')
    bad("  Ava 1 1\n", 'after a formation')
    bad(BASE.sub(/formation End.*/m, ''), 'at least two formations')
    bad('hello', 'after a formation')
  end
end

class TestPlanner < Minitest::Test
  EXAMPLE = File.expand_path('../examples/opening.txt', __dir__)

  def test_the_example_plans_cleanly_and_carries_positions_through
    show = Crosscue::Parser.parse(File.read(EXAMPLE))
    changes = Crosscue::Planner.plan(show)
    assert_equal 2, changes.size
    hana = changes[0].moves.find { |m| m.dancer == 'Hana' }
    assert_equal [8.0, 3.0], hana.to, 'the pinned dancer ends on her spot'
    changes[0].moves.each do |m|
      later = changes[1].moves.find { |x| x.dancer == m.dancer }
      assert_equal m.to, later.from, "#{m.dancer} starts change 2 where change 1 left them"
    end
    changes.each do |c|
      assert_empty c.conflicts
      assert_operator c.needed_counts, :<=, c.counts
      c.moves.each { |m| assert_operator m.finish - m.start, :>=, (m.distance / show.pace / show.beat).ceil }
    end
    text = Crosscue::Report.render(show, changes)
    assert_includes text, 'Every change fits its counts'
    assert_includes text, 'audience'
  end

  def test_a_change_that_is_too_fast_is_called_out
    text = File.read(EXAMPLE).sub('in 6 counts', 'in 2 counts')
    show = Crosscue::Parser.parse(text)
    report = Crosscue::Report.render(show, Crosscue::Planner.plan(show))
    assert_includes report, 'TOO FAST'
  end

  def test_map_keeps_every_label
    show = Crosscue::Parser.parse(File.read(EXAMPLE))
    crowd = show.dancers.to_h { |d| [d, [5.0, 4.0]] } # everyone on one spot
    map = Crosscue::Report.map(show, crowd)
    show.dancers.each { |d| assert_includes map, d[0, 2] }
  end
end

class TestCommandLine < Minitest::Test
  BIN = File.expand_path('../bin/crosscue', __dir__)
  EXAMPLE = File.expand_path('../examples/opening.txt', __dir__)

  def run_cli(*args, stdin: nil)
    Open3.capture3(RbConfig.ruby, BIN, *args, stdin_data: stdin.to_s)
  end

  def test_example_and_stdin
    out, _, st = run_cli(EXAMPLE)
    assert_equal 0, st.exitstatus
    assert_match(/^CROSSCUE /, out)
    out2, _, st2 = run_cli('-', stdin: File.read(EXAMPLE))
    assert_equal 0, st2.exitstatus
    assert_equal out, out2
  end

  def test_refuses_unsafe_files
    Dir.mktmpdir do |dir|
      link = File.join(dir, 'link.txt')
      File.symlink(EXAMPLE, link)
      assert_match(/symbolic link/, run_cli(link)[1])
      assert_match(/not a regular file/, run_cli(dir)[1])
      assert_match(/not a regular file/, run_cli('/dev/zero')[1])
      big = File.join(dir, 'big.txt')
      File.write(big, '#' * 70_000)
      assert_match(/larger than 64 KB/, run_cli(big)[1])
      _, err, st = run_cli(File.join(dir, "missing\e[31m.txt"))
      assert_equal 2, st.exitstatus
      assert_includes err, 'missing??31m.txt does not exist'
      refute_includes err, "\e"
      assert_equal 2, run_cli('-', stdin: '#' * 70_000)[2].exitstatus
      assert_equal 2, run_cli[2].exitstatus
    end
  end
end
