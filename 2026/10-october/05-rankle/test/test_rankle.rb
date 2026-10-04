# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require 'tempfile'
require_relative '../lib/rankle'

class RankleTest < Minitest::Test
  M = Rankle::Methods
  A = Rankle::Analysis

  FIVE = File.read(File.join(__dir__, '..', 'examples', 'five-winners.txt'))
  LUNCH = "4: Pizza > Sushi > Tacos\n3: Sushi > Tacos > Pizza\n2: Tacos > Pizza > Sushi\n"

  def parse(text) = Rankle::Ballots.parse(text)

  def run_cli(*argv, stdin: '')
    out = StringIO.new
    err = StringIO.new
    code = Rankle.run(argv, stdin: StringIO.new(stdin), out: out, err: err)
    [code, out.string, err.string]
  end

  # ---- parsing ------------------------------------------------------------

  def test_parses_counts_comments_and_blank_lines
    candidates, ballots = parse("# title\n\n3: A > B\nB > A   # one voter\n")
    assert_equal %w[A B], candidates
    assert_equal [3, 1], ballots.map(&:count)
    assert_equal [%w[A B], %w[B A]], ballots.map(&:ranking)
  end

  def test_names_may_contain_spaces_accents_and_other_scripts
    candidates, = parse("Zoë  O'Neil > 李雷 > Jean-Luc\nJean-Luc > 李雷\n")
    assert_equal ["Zoë O'Neil", '李雷', 'Jean-Luc'], candidates
  end

  def test_windows_line_endings
    candidates, ballots = parse("2: A > B\r\n1: B > A\r\n")
    assert_equal %w[A B], candidates
    assert_equal 2, ballots.size
  end

  # ---- the five rules -----------------------------------------------------

  def test_classic_example_elects_five_different_winners
    candidates, ballots = parse(FIVE)
    assert_equal(
      { 'Plurality' => ['Ana'], 'Two-round runoff' => ['Bo'], 'Instant runoff' => ['Cai'],
        'Borda count' => ['Dev'], 'Condorcet' => ['Eli'] },
      A.results(candidates, ballots)
    )
  end

  def test_borda_scores_match_hand_calculation
    candidates, ballots = parse(FIVE)
    scores = M.borda_scores(candidates, ballots)
    assert_equal({ 'Ana' => 72, 'Bo' => 101, 'Cai' => 107, 'Dev' => 136, 'Eli' => 134 }, scores)
    assert_equal 55 * (4 + 3 + 2 + 1), scores.values.sum
  end

  def test_pairwise_counts_add_up_to_the_number_of_voters
    candidates, ballots = parse(FIVE)
    matrix = M.pairwise(candidates, ballots)
    candidates.combination(2) { |a, b| assert_equal 55, matrix[a][b] + matrix[b][a] }
  end

  def test_majority_winner_wins_everywhere
    candidates, ballots = parse("6: A > B > C\n3: B > A > C\n1: C > A > B\n")
    assert_equal [['A']], A.results(candidates, ballots).values.uniq
    assert_empty A.spoilers(candidates, ballots)
  end

  def test_exact_tie_is_reported_as_a_tie
    candidates, ballots = parse("1: A > B\n1: B > A\n")
    assert_equal %w[A B], M.plurality(candidates, ballots)
    assert_equal %w[A B], M.runoff(candidates, ballots)
    assert_equal %w[A B], M.instant_runoff(candidates, ballots)
    assert_equal %w[A B], M.borda(candidates, ballots)
    assert_empty M.condorcet(candidates, ballots)
  end

  def test_truncated_ballots_rank_unlisted_candidates_last
    candidates, ballots = parse("3: A\n2: B > C\n2: C > B\n")
    assert_equal ['A'], M.plurality(candidates, ballots)
    # B and C voters never listed A, so A loses both head-to-heads 3-4.
    assert_equal 'A', A.condorcet_loser(candidates, ballots)
    matrix = M.pairwise(candidates, ballots)
    assert_equal [3, 4], [matrix['A']['B'], matrix['B']['A']]
  end

  def test_instant_runoff_handles_exhausted_ballots
    candidates, ballots = parse("4: A\n3: B > C\n2: C > B\n")
    assert_equal ['B'], M.instant_runoff(candidates, ballots)
  end

  def test_instant_runoff_always_terminates_on_a_full_tie
    candidates, ballots = parse("1: A > B > C\n1: B > C > A\n1: C > A > B\n")
    assert_equal %w[A B C], M.instant_runoff(candidates, ballots)
  end

  # ---- paradoxes and spoilers --------------------------------------------

  def test_detects_a_condorcet_cycle
    candidates, ballots = parse(LUNCH)
    assert_empty M.condorcet(candidates, ballots)
    cycle = A.cycle(candidates, ballots)
    assert_equal %w[Pizza Sushi Tacos], cycle
  end

  def test_no_cycle_when_there_is_a_condorcet_winner
    candidates, ballots = parse(FIVE)
    assert_nil A.cycle(candidates, ballots)
  end

  def test_finds_the_textbook_spoiler
    # Left and Centre split the majority; Right wins. Remove Centre and Left wins.
    candidates, ballots = parse("40: Right\n35: Left > Centre\n25: Centre > Left\n")
    spoilers = A.spoilers(candidates, ballots).select { |s| s.method_name == 'Plurality' }
    assert_includes spoilers.map { |s| [s.candidate, s.before, s.after] }, ['Centre', ['Right'], ['Left']]
  end

  def test_condorcet_never_has_a_spoiler_when_a_winner_exists
    candidates, ballots = parse(FIVE)
    assert_empty(A.spoilers(candidates, ballots).select { |s| s.method_name == 'Condorcet' })
  end

  def test_condorcet_loser_warning_appears_in_report
    candidates, ballots = parse(FIVE)
    report = Rankle::Report.render(candidates, ballots)
    assert_includes report, 'Ana loses one-on-one to every other candidate, yet wins under Plurality'
    assert_includes report, '5 different outcomes'
  end

  def test_results_do_not_depend_on_ballot_order
    candidates, ballots = parse(FIVE)
    expected = A.results(candidates, ballots)
    20.times do |seed|
      shuffled = ballots.shuffle(random: Random.new(seed))
      assert_equal expected, A.results(candidates, shuffled)
    end
  end

  # ---- command line -------------------------------------------------------

  def test_exit_codes
    Tempfile.create('ballots') do |file|
      file.write("2: A > B\n1: B > A\n")
      file.flush
      assert_equal 0, run_cli(file.path).first
    end
    assert_equal 1, run_cli('-', stdin: LUNCH).first
    assert_equal 2, run_cli.first
    assert_equal 2, run_cli('a', 'b').first
    assert_equal 0, run_cli('--help').first
  end

  def test_missing_file_and_directory_give_a_clean_error
    ['/no/such/file', '/', Dir.tmpdir, "\0", '../../../../etc/shadow'].each do |path|
      code, out, err = run_cli(path)
      assert_equal 2, code
      assert_empty out
      assert_equal "rankle: cannot read that file\n", err
    end
  end

  # ---- hostile input ------------------------------------------------------

  def assert_rejected(text, pattern = //)
    error = assert_raises(Rankle::InputError) { parse(text) }
    assert_match pattern, error.message
  end

  def test_rejects_terminal_escape_codes_and_control_characters
    ["\e[2J\e[31mA > B", "A\a > B", "A\t\u0000 > B", "A‮ > B", "A > B C"].each do |text|
      assert_rejected text, /control characters are not allowed|invalid candidate name/
    end
  end

  def test_rejects_markup_shell_and_path_characters_in_names
    ['<script>alert(1)</script> > B', '$(rm -rf ~) > B', '`id` > B', 'A; ls > B', '../../etc/passwd > B',
     'A | B > C', '%s%n > B', '"A" > B'].each do |text|
      assert_rejected text, /invalid candidate name|empty candidate name/
    end
  end

  def test_error_messages_never_echo_the_input
    error = assert_raises(Rankle::InputError) { parse("\e]0;owned\a > B") }
    refute_match(/owned|\e/, error.message)
  end

  def test_rejects_bad_structure
    assert_rejected '', /no ballots/
    assert_rejected "# only a comment\n", /no ballots/
    assert_rejected 'A', /at least two candidates/
    assert_rejected 'A > A', /ranked twice/
    assert_rejected 'A > > B', /empty candidate name/
    assert_rejected '> A', /empty candidate name/
    assert_rejected '0: A > B', /count must be/
    assert_rejected '-5: A > B', /invalid candidate name/
    assert_rejected '99999999999: A > B', /invalid candidate name/
    assert_rejected "#{'A' * 41} > B", /invalid candidate name/
  end

  def test_rejects_oversized_input
    assert_rejected "A > B\n" * 10_001, /lines/
    assert_rejected "#{'x' * 1_000_001}", /larger than/
    assert_rejected (1..21).map { |i| "C#{i}" }.join(' > '), /more than 20 candidates/
    assert_rejected "1000000000: A > B\n1: B > A\n", /voters in total/
  end

  def test_rejects_invalid_utf8_and_non_strings
    assert_rejected "A > \xFF\xFE".b, /UTF-8/
    assert_rejected nil, /not text/
    assert_rejected 42, /not text/
  end

  def test_huge_stdin_is_cut_off_not_loaded
    code, _, err = run_cli('-', stdin: 'A > B ' * 400_000)
    assert_equal 2, code
    assert_match(/larger than/, err)
  end

  def test_parser_is_fast_on_pathological_lines
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    assert_raises(Rankle::InputError) { parse("#{'1' * 5000}:#{' ' * 5000}#{'>' * 5000}") }
    assert_raises(Rankle::InputError) { parse("#{'a ' * 100_000}!") }
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.0
  end

  def test_largest_allowed_election_finishes_quickly
    names = (1..20).map { |i| "C#{i}" }
    random = Random.new(7)
    text = Array.new(2000) { "#{random.rand(1..500)}: #{names.shuffle(random: random).join(' > ')}" }.join("\n")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    candidates, ballots = parse(text)
    Rankle::Report.render(candidates, ballots)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10.0
  end
end
