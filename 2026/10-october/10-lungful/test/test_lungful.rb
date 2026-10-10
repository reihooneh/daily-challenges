# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../lib/lungful'

EXAMPLE = File.expand_path('../examples/tidepool-demo.md', __dir__)

class SpokenTest < Minitest::Test
  # Common words with dictionary syllable counts.
  KNOWN = {
    'cat' => 1, 'make' => 1, 'hoped' => 1, 'yes' => 1, 'table' => 2, 'little' => 2, 'water' => 2,
    'happy' => 2, 'student' => 2, 'problem' => 2, 'summer' => 2, 'record' => 2, 'people' => 2,
    'computer' => 3, 'beautiful' => 3, 'family' => 3, 'important' => 3, 'hospital' => 3,
    'information' => 4, 'technology' => 4, 'emergency' => 4, 'university' => 5,
    'department' => 3, 'warning' => 2, 'creature' => 2, 'distance' => 2, 'explore' => 2,
    'thousand' => 2, 'holiday' => 3, 'camera' => 3, 'octopus' => 3, 'prototype' => 3,
    'volunteer' => 3, 'supervisor' => 4, 'second' => 2, 'science' => 2, 'medicine' => 3,
    'pharmacy' => 3, 'device' => 2, 'signal' => 2, 'model' => 2, 'testing' => 2, 'lifeguard' => 2,
    'simple' => 2, 'together' => 3, 'remember' => 3, 'yesterday' => 3, 'banana' => 3,
    'elephant' => 3, 'tomato' => 3, 'potato' => 3, 'animal' => 3, 'library' => 3,
    'school' => 1, 'rock' => 1, 'pool' => 1, 'phone' => 1, 'beach' => 1, 'shell' => 1,
    'safe' => 1, 'touch' => 1, 'trip' => 1, 'red' => 1
  }.freeze

  def test_syllables_match_a_dictionary_for_most_common_words
    right = KNOWN.count { |w, n| Lungful::Spoken.syllables(w) == n }
    assert_operator right, :>=, (KNOWN.size * 0.85).ceil, "only #{right} of #{KNOWN.size} right"
  end

  def test_numbers_in_words
    s = Lungful::Spoken
    assert_equal 'zero', s.number_words(0)
    assert_equal 'forty-two', s.number_words(42)
    assert_equal 'one hundred and five', s.number_words(105)
    assert_equal 'two hundred and twenty-two thousand four hundred and seventy-five', s.number_words(222_475)
    assert_equal 'one million', s.number_words(1_000_000)
    assert_equal 'three thousand and seven', s.number_words(3007)
  end

  def test_years_money_percentages_and_acronyms
    s = Lungful::Spoken
    assert_equal 'twenty twenty-one', s.expand('2021')
    assert_equal 'nineteen ninety-eight', s.expand('1998')
    assert_equal 'two thousand and five', s.expand('2005')
    assert_equal 'nineteen oh seven', s.expand('1907')
    assert_equal 'four dollars fifty', s.expand('$4.50')
    assert_equal 'one dollar', s.expand('$1')
    assert_equal 'seventy-three point seven per cent', s.expand('73.7%')
    assert_equal 'A B S', s.expand('ABS')
    assert_nil s.expand('hello')
    assert_nil s.expand('9' * 13), 'absurdly long numbers are left alone'
    assert_equal 5, s.token_syllables('NSW'), 'W is three syllables'
    assert_equal 15, s.token_syllables('222,475')
  end
end

class ScriptTest < Minitest::Test
  def test_phrases_split_at_punctuation_and_skip_directions
    phrases = Lungful::Script.phrases_of('Hi, I am Sam. [ON SCREEN: logo] This is it — really (pause) done')
    assert_equal [%w[Hi], %w[I am Sam], %w[This is it], %w[really], %w[done]], phrases.map { |p| p.words.map(&:text) }
    assert_equal [0.3, 0.6, 0.4, 1.0, 0.0], phrases.map(&:pause)
  end

  def test_sections_targets_and_opening_text
    sections = Lungful::Script.parse("Before any heading.\n\n# One [1:30]\nHello there.\n## Two\nBye.\n")
    assert_equal ['Opening', 'One', 'Two'], sections.map(&:title)
    assert_equal [nil, 90, nil], sections.map(&:target)
    assert_equal 1.0, sections[1].paragraphs.last.last.pause, 'a paragraph ends with a longer pause'
  end

  def rejects(text, message)
    error = assert_raises(Lungful::InputError) { Lungful::Script.parse(text) }
    assert_includes error.message, message
    error.message
  end

  def test_hostile_scripts
    rejects("Hello\e[2J world\n", 'control or invisible')
    rejects("Hello ‮dlrow\n", 'control or invisible')
    rejects("Zero​width\n", 'control or invisible')
    rejects("Nul\u0000byte\n", 'control or invisible')
    rejects("a\n" * 40_000, 'larger than 64 KB')
    rejects("#{'a' * 2001}\n", 'longer than 2000')
    rejects("\xFF\xFEbad".dup.force_encoding('UTF-8'), 'not valid UTF-8')
    rejects("# Only a heading\n", 'nothing to say')
    rejects("# #{'T' * 61}\nHi.\n", 'longer than 60')
    rejects((1..51).map { |i| "# S#{i}\nHi.\n" }.join, 'too many sections')
    rejects(("w " * 600 + "\n") * 21, 'more than 12000 words')
    message = rejects("<script>alert(1)</script>\e]0;owned\a\n", 'control or invisible')
    refute_includes message, 'owned'
  end

  def test_unicode_punctuation_is_fine
    sections = Lungful::Script.parse("Café — naïve “quotes” and ‘apostrophes’ work.\n")
    assert_equal 1, sections.length
  end
end

class AnalysisTest < Minitest::Test
  W = Lungful::Script::Word

  def words(*pairs) = pairs.each_slice(2).map { |t, s| W.new(t, s) }

  def test_split_points_keep_every_piece_within_the_limit
    rng = Random.new(5)
    300.times do
      list = Array.new(rng.rand(2..60)) { W.new(%w[the and data which river but sky to].sample(random: rng), rng.rand(1..5)) }
      limit = rng.rand(12..40)
      cuts = Lungful::Analysis.split_points(list, limit)
      pieces = ([0] + cuts + [list.length]).each_cons(2).map { |a, b| list[a...b] }
      pieces.each do |piece|
        assert(piece.sum(&:syllables) <= limit || piece.length == 1, 'a piece is still too long')
      end
      assert_equal cuts.sort.uniq, cuts, 'cuts are in order and distinct'
    end
  end

  def test_split_prefers_a_joint_word_near_the_middle
    list = words('alpha', 4, 'beta', 4, 'gamma', 4, 'and', 1, 'delta', 4, 'epsilon', 4, 'zeta', 4)
    assert_equal [3], Lungful::Analysis.split_points(list, 20)
  end

  def test_timing_is_syllables_over_rate_plus_pauses
    sections = Lungful::Script.parse("# A [0:10]\nOne two three, four five.\n")
    result = Lungful::Analysis.run(sections, rate: 4.0, limit: 24)
    # 5 one-syllable words at 4 per second, a comma (0.3) and a full stop that ends the paragraph (1.0)
    assert_in_delta 5 / 4.0 + 0.3 + 1.0, result.sections.first.seconds, 1e-9
  end

  def test_tricky_spots
    phrase = Lungful::Script.phrases_of('In 2023 we counted 31,742 stings and she sells seashells near ABS NSW 2021 data').first
    kinds = Lungful::Analysis.tricky_spots('S', phrase).map(&:kind)
    assert_includes kinds, :number
    assert_includes kinds, :twister
    assert_includes kinds, :pile_up
    assert_equal '220,000', Lungful::Analysis.rounded('222,475')
    assert_equal '32,000', Lungful::Analysis.rounded('31,742')
    assert_equal '1.2 million', Lungful::Analysis.rounded('1,234,567')
    assert_equal '99', Lungful::Analysis.rounded('99')
  end

  def test_the_largest_allowed_script_is_quick
    text = (1..35).map { |i| "# Part #{i} [0:30]\n" + ("word and another " * 99) + "\n" }.join
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = Lungful::Analysis.run(Lungful::Script.parse(text), rate: 3.8, limit: 24)
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
    refute_empty result.breaths
  end
end

class ReportTest < Minitest::Test
  def test_verdicts
    assert_equal 'on time', Lungful::Report.verdict(60, 65)
    assert_match(/too long, cut about 27 words/, Lungful::Report.verdict(60, 70))
    assert_match(/short, room for about/, Lungful::Report.verdict(60, 40))
    assert_equal '', Lungful::Report.verdict(nil, 40)
    assert_equal '1:05', Lungful::Report.clock(65)
  end
end

class CommandLineTest < Minitest::Test
  def run_cli(args, stdin = '')
    out = StringIO.new
    err = StringIO.new
    code = Lungful.main(args, stdin: StringIO.new(stdin), out: out, err: err)
    [code, out.string, err.string]
  end

  def test_the_example_report
    code, out, err = run_cli([EXAMPLE])
    assert_equal 1, code
    assert_empty err
    assert_includes out, 'The problem      0:20      0:27   +33% too long'
    assert_includes out, 'Breathe before "without", "and", "to".'
    assert_includes out, 'Try "about 32,000"'
    assert_includes out, '"She sells seashells"'
  end

  def test_marked_script_and_standard_input
    code, out, = run_cli(['--marked', '-'], "# Go\nA short line that is fine.\n")
    assert_equal 0, code
    assert_includes out, 'Ready to record.'
    assert_includes out, '## Go'
    _, marked, = run_cli(['--marked', EXAMPLE])
    assert_includes marked, 'rock pools / without'
  end

  def test_bad_arguments_give_one_clean_error
    Dir.mktmpdir do |dir|
      big = File.join(dir, 'big.md')
      File.write(big, 'a' * 70_000)
      cases = [[], %w[a b], ['--rate'], %w[--rate 9], %w[--rate 1e3], %w[--breath 5], ['--bogus'],
               ['/no/such/file'], [dir], [big], ['/dev/zero'], ["\e]0;owned\a$(reboot)"]]
      cases.each do |args|
        code, out, err = run_cli(args)
        assert_equal 2, code, args.inspect
        assert_empty out
        assert err.start_with?('lungful: '), err
        refute_includes err, 'owned'
        refute_includes err, 'reboot'
      end
    end
  end

  def test_odd_file_names_are_not_printed_raw
    Dir.mktmpdir do |dir|
      path = File.join(dir, "bad\e[31mname.md")
      File.write(path, "Hello.\n")
      _, out, = run_cli([path])
      refute_includes out, "\e"
    end
  end
end
