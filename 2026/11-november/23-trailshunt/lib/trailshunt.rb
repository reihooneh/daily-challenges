# frozen_string_literal: true

require 'json'

# Trailshunt: gets a walking group and its cars from one end of a one-way hike to the other and
# back, with the least driving: either shuttling cars to the far end first, or splitting the group
# to walk from both ends and swap car keys when they meet in the middle.
module Trailshunt
  class PlanError < StandardError; end

  MAX_PEOPLE = 40
  MAX_CARS = 14
  MAX_BYTES = 64 * 1024
  NAME = /\A[\p{L}\p{N} .,'&()-]{1,30}\z/

  Person = Struct.new(:name, :licence, keyword_init: true)
  Car = Struct.new(:name, :seats, :owner, keyword_init: true)
  Trail = Struct.new(:start, :finish, :drive_km, :drive_min, keyword_init: true)
  Group = Struct.new(:people, :cars, :trail, keyword_init: true)

  # A shuttle: cars `parked` go to the finish first, and `ferry` brings their drivers back.
  Shuttle = Struct.new(:parked, :ferry, keyword_init: true) do
    def legs = (parked.size * 2) + 2
  end

  # A key swap: team `out` drives `cars` to the finish and walks back; team `in` walks from the start.
  KeySwap = Struct.new(:cars, :out_team, :in_team, keyword_init: true) do
    def legs = cars.size * 2
  end

  module_function

  def check_name(value, what)
    raise PlanError, "#{what} must be a short name" unless value.is_a?(String) && NAME.match?(value)

    value
  end

  def number(value, low, high, what)
    unless value.is_a?(Numeric) && value.finite? && value.between?(low, high)
      raise PlanError, "#{what} must be a number from #{low} to #{high}"
    end

    value
  end

  def parse(text)
    raise PlanError, 'the file is larger than 64 KB' if text.bytesize > MAX_BYTES

    data = begin
      JSON.parse(text, max_nesting: 10, create_additions: false)
    rescue JSON::ParserError, JSON::NestingError
      raise PlanError, "the file isn't valid JSON"
    end
    raise PlanError, 'the file must be a JSON object' unless data.is_a?(Hash)

    t = data['trail']
    raise PlanError, 'trail must describe the walk' unless t.is_a?(Hash)

    trail = Trail.new(start: check_name(t['start'], 'trail start'), finish: check_name(t['finish'], 'trail finish'),
                      drive_km: number(t['drive_km'], 0.1, 1000, 'drive_km'),
                      drive_min: number(t['drive_min'], 1, 1000, 'drive_min'))
    people = data['people']
    unless people.is_a?(Array) && people.size.between?(1, MAX_PEOPLE)
      raise PlanError, "people must list 1 to #{MAX_PEOPLE} walkers"
    end

    people = people.map do |p|
      raise PlanError, 'each person must be an object' unless p.is_a?(Hash)

      licence = p.fetch('licence', true)
      raise PlanError, "#{p['name']}: licence must be true or false" unless [true, false].include?(licence)

      Person.new(name: check_name(p['name'], 'a name'), licence: licence)
    end
    cars = data['cars']
    raise PlanError, "cars must list 1 to #{MAX_CARS} cars" unless cars.is_a?(Array) && cars.size.between?(1, MAX_CARS)

    cars = cars.map do |c|
      raise PlanError, 'each car must be an object' unless c.is_a?(Hash)

      seats = number(c['seats'], 2, 9, "#{c['name']}: seats")
      raise PlanError, "#{c['name']}: seats must be a whole number" unless seats.is_a?(Integer)

      owner = c['owner']
      owner = check_name(owner, "#{c['name']}: owner") unless owner.nil?
      Car.new(name: check_name(c['name'], 'a car'), seats: seats, owner: owner)
    end
    cars.each do |c|
      next if c.owner.nil?

      who = people.find { |p| p.name == c.owner }
      raise PlanError, "#{c.name}: owner #{c.owner} isn't walking" unless who
      raise PlanError, "#{c.name}: owner #{c.owner} has no licence" unless who.licence
    end
    raise PlanError, 'two people share a name' unless people.map(&:name).uniq.size == people.size
    raise PlanError, 'two cars share a name' unless cars.map(&:name).uniq.size == cars.size
    if cars.sum(&:seats) < people.size
      raise PlanError, "the cars seat #{cars.sum(&:seats)} but #{people.size} are walking"
    end

    Group.new(people: people, cars: cars, trail: trail)
  end

  def seats(cars) = cars.sum(&:seats)

  # The shuttle with the fewest cars parked at the finish: they must seat everyone after the walk,
  # and the ferry car must bring their drivers back, with a licensed driver for every car that moves.
  def best_shuttle(group)
    licensed = group.people.count(&:licence)
    everyone = group.people.size
    best = nil
    group.cars.each do |ferry|
      others = group.cars - [ferry]
      (1..others.size).each do |k|
        break if best && k >= best.parked.size
        next if ferry.seats < k + 1 || licensed < k + 1

        parked = others.combination(k).select { |set| seats(set) >= everyone }.max_by { |set| [seats(set), -set.size] }
        best = Shuttle.new(parked: parked, ferry: ferry) if parked && (best.nil? || k < best.parked.size)
      end
    end
    best
  end

  # The key swap with the fewest cars taken to the finish. Only the team sizes and how many in each
  # team can drive matter, so after choosing the cars it is a small search over those two numbers.
  def best_key_swap(group)
    n = group.people.size
    licensed = group.people.select(&:licence)
    unlicensed = group.people.reject(&:licence)
    return nil if n < 4 # each team walks as at least a pair

    (1...group.cars.size).each do |k|
      choices = group.cars.combination(k).sort_by { |set| -seats(set) }
      choices.each do |cars|
        cap = seats(cars)
        best = nil
        (2..(n - 2)).each do |out|
          (k..[out, licensed.size].min).each do |lic_out|
            unlic_out = out - lic_out
            next if unlic_out > unlicensed.size || licensed.size - lic_out < k
            # the out team drives these cars to the finish; the in team drives them back
            next if out > cap || n - out > cap

            score = (2 * out - n).abs
            best = [score, out, lic_out] if best.nil? || score < best[0]
          end
        end
        next unless best

        _, out, lic_out = best
        # Owners of the cars going to the finish drive their own cars there, so they go first.
        owners = cars.filter_map(&:owner)
        drivers = licensed.sort_by { |p| owners.include?(p.name) ? 0 : 1 }
        out_team = drivers.first(lic_out) + unlicensed.first(out - lic_out)
        return KeySwap.new(cars: cars, out_team: out_team, in_team: group.people - out_team)
      end
    end
    nil
  end

  def plan(group)
    { shuttle: best_shuttle(group), key_swap: best_key_swap(group) }
  end
end
