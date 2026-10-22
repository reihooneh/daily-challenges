# frozen_string_literal: true

module Crosscue
  # The printed run sheet: one block per change, with a map of where everyone ends up.
  module Report
    MAP_COLS = 41
    MAP_ROWS = 11

    module_function

    def render(show, changes)
      out = +"CROSSCUE  #{show.name}\n"
      out << format("%d dancers on a %s x %s m stage, %d counts a minute, walking up to %.1f m/s.\n",
                    show.dancers.size, num(show.width), num(show.depth), show.tempo, show.pace)
      changes.each_with_index do |c, i|
        out << "\n" << change(show, c, i + 1)
      end
      problems = changes.count { |c| c.needed_counts > c.counts || !c.conflicts.empty? }
      out << "\n" << (problems.zero? ? "Every change fits its counts with room to pass.\n" : "#{problems} change(s) need attention (see above).\n")
      out
    end

    def change(show, c, number)
      seconds = c.counts * show.beat
      out = +format("Change %d: %s -> %s, %d counts (%.1f s)\n", number, c.from_name, c.to_name, c.counts, seconds)
      width = [show.dancers.map(&:length).max, 6].max
      out << format("  %-*s  %-12s %-12s %7s   %s\n", width, 'Dancer', 'From', 'To', 'Walk', 'Go on count')
      c.moves.each do |m|
        go = if !m.moving? then 'stay'
             elsif m.start.positive? then "#{m.start.to_i + 1} (wait #{m.start.to_i})"
             elsif m.finish < c.counts then "1 (be there by #{m.finish.to_i})"
             else '1'
             end
        out << format("  %-*s  %-12s %-12s %5.1f m   %s\n", width, m.dancer, pos(m.from), pos(m.to), m.distance, go)
      end
      out << format("  Longest walk %.1f m (needs %d counts at your pace); everyone together walks %.1f m.\n",
                    c.longest, c.needed_counts, c.total)
      if c.needed_counts > c.counts
        out << "  TOO FAST: the longest walk needs #{c.needed_counts} counts; the music gives #{c.counts}. " \
               "Give this change more counts or move the far spots closer.\n"
      end
      retimed = c.moves.select { |m| m.moving? && (m.start.positive? || m.finish < c.counts) }
      unless retimed.empty?
        notes = retimed.map do |m|
          m.start.positive? ? "#{m.dancer} waits #{m.start.to_i} counts" : "#{m.dancer} arrives by count #{m.finish.to_i}"
        end
        out << "  To pass cleanly: #{notes.join('; ')}.\n"
      end
      c.conflicts.each do |k|
        out << format("  CLOSE: %s and %s pass %.2f m apart around count %d. Swap their spots or curve one path.\n",
                      k[:pair][0], k[:pair][1], k[:distance], k[:count].floor + 1)
      end
      out << map(show, c.moves.to_h { |m| [m.dancer, m.to] })
    end

    # Top view, as the audience sees it: back of the stage at the top, the audience below.
    def map(show, where)
      grid = Array.new(MAP_ROWS) { Array.new(MAP_COLS, ' ') }
      where.sort_by { |_, (x, _)| x }.each do |name, (x, y)|
        row = ((show.depth - y) / show.depth * (MAP_ROWS - 1)).round.clamp(0, MAP_ROWS - 1)
        col = (x / show.width * (MAP_COLS - 2)).round.clamp(0, MAP_COLS - 2)
        label = name[0, 2]
        # Keep labels apart: move right (then left) to the nearest free pair of cells.
        offsets = (0..MAP_COLS).flat_map { |d| [d, -d] }.uniq
        spot = offsets.map { |d| col + d }.find { |cc| cc >= 0 && cc + 1 < MAP_COLS && grid[row][cc] == ' ' && grid[row][cc + 1] == ' ' }
        next unless spot

        grid[row][spot] = label[0]
        grid[row][spot + 1] = label[1] || '.'
      end
      border = "   +#{'-' * MAP_COLS}+\n"
      body = grid.map { |r| "   |#{r.join}|\n" }.join
      "   back of the stage\n#{border}#{body}#{border}   audience\n"
    end

    def pos(p)
      format('(%s, %s)', num(p[0]), num(p[1]))
    end

    def num(v)
      v == v.round ? v.round.to_s : format('%.1f', v)
    end
  end
end
