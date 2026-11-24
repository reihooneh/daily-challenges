# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require_relative '../lib/trailshunt'
load File.expand_path('../bin/trailshunt', __dir__)

class TestTrailshunt < Minitest::Test
  EXAMPLE = File.read(File.expand_path('../examples/ridge.json', __dir__))

  def group(people:, cars:)
    Trailshunt.parse(JSON.generate(
                       'trail' => { 'start' => 'A', 'finish' => 'B', 'drive_km' => 10, 'drive_min' => 15 },
                       'people' => people.each_with_index.map { |lic, i| { 'name' => "p#{i}", 'licence' => lic } },
                       'cars' => cars.each_with_index.map { |s, i| { 'name' => "c#{i}", 'seats' => s } }
                     ))
  end

  def test_example
    text = Trailshunt::CLI.report(Trailshunt.parse(EXAMPLE))
    assert_includes text, 'Shuttle: 6 drives'
    assert_includes text, 'Key swap: 2 drives'
    assert_includes text, "1. Hiro, Elif, Finn, Isla drive Hiro's van"
  end

  # A shuttle is valid if the parked cars seat everyone, the ferry seats their drivers, and there
  # are enough licensed drivers for every car that moves.
  def shuttle_ok?(g, parked, ferry)
    !parked.include?(ferry) && Trailshunt.seats(parked) >= g.people.size && ferry.seats >= parked.size + 1 &&
      g.people.count(&:licence) >= parked.size + 1
  end

  # A key swap is valid for a team split if each team fits the cars and has a driver for each.
  def swap_ok?(_g, cars, out_team, in_team)
    out_team.size >= 2 && in_team.size >= 2 && Trailshunt.seats(cars) >= out_team.size &&
      Trailshunt.seats(cars) >= in_team.size && out_team.count(&:licence) >= cars.size &&
      in_team.count(&:licence) >= cars.size
  end

  def same(want, got)
    want.nil? ? assert_nil(got) : assert_equal(want, got)
  end

  def test_matches_brute_force
    rng = Random.new(8)
    60.times do
      g = group(people: Array.new(rng.rand(2..8)) { rng.rand < 0.7 }, cars: Array.new(rng.rand(1..5)) { rng.rand(2..7) })
    rescue Trailshunt::PlanError
      next
    else
      shuttle = Trailshunt.best_shuttle(g)
      brute = g.cars.flat_map do |ferry|
        (1..g.cars.size).flat_map { |k| (g.cars - [ferry]).combination(k).to_a }.select { |set| shuttle_ok?(g, set, ferry) }
      end.map(&:size).min
      same(brute, shuttle&.parked&.size)

      swap = Trailshunt.best_key_swap(g)
      best = nil
      (1...g.cars.size).each do |k|
        g.cars.combination(k).each do |cars|
          (0..g.people.size).each do |n|
            g.people.combination(n).each do |out|
              best = k if swap_ok?(g, cars, out, g.people - out) && (best.nil? || k < best)
            end
          end
        end
      end
      same(best, swap&.cars&.size)
      assert swap_ok?(g, swap.cars, swap.out_team, swap.in_team) if swap
    end
  end

  def test_owners_drive_their_own_cars
    g = Trailshunt.parse(EXAMPLE)
    swap = Trailshunt.best_key_swap(g)
    swap.cars.each { |c| assert_includes swap.out_team.map(&:name), c.owner }
  end

  def test_too_few_seats_or_drivers
    assert_raises(Trailshunt::PlanError) { group(people: [true] * 6, cars: [4]) }
    g = group(people: [true, false, false], cars: [4, 4])
    assert_nil Trailshunt.best_key_swap(g)
    assert_nil Trailshunt.best_shuttle(g) # one licensed driver can't move two cars
  end

  def test_hostile_files
    base = JSON.parse(EXAMPLE)
    bad = [
      'nope', '[]', '{"json_class":"File","a":1}', '[' * 50,
      JSON.generate(base.merge('trail' => base['trail'].merge('drive_km' => Float::INFINITY.to_s))),
      JSON.generate(base.merge('trail' => base['trail'].merge('drive_km' => -5))),
      JSON.generate(base.merge('people' => [{ 'name' => "<script>alert(1)</script>" }])),
      JSON.generate(base.merge('people' => [{ 'name' => "A\e[31m" }])),
      JSON.generate(base.merge('people' => base['people'] + [{ 'name' => 'Amira' }])),
      JSON.generate(base.merge('people' => [{ 'name' => 'Zed', 'licence' => 'yes' }])),
      JSON.generate(base.merge('cars' => [{ 'name' => 'X', 'seats' => 4.5 }])),
      JSON.generate(base.merge('cars' => [{ 'name' => 'X', 'seats' => 40 }])),
      JSON.generate(base.merge('cars' => [{ 'name' => 'X', 'seats' => 5, 'owner' => 'Nobody' }])),
      JSON.generate(base.merge('cars' => [{ 'name' => 'X', 'seats' => 5, 'owner' => 'Elif' }])),
      JSON.generate(base.merge('people' => Array.new(41) { |i| { 'name' => "p#{i}" } })),
      'x' * 70_000
    ]
    bad.each { |text| assert_raises(Trailshunt::PlanError, text[0, 60]) { Trailshunt.parse(text) } }
  end

  def test_cli_refuses_odd_paths
    assert_equal 2, Trailshunt::CLI.main([])
    assert_equal 2, Trailshunt::CLI.main([__dir__])
  end
end
