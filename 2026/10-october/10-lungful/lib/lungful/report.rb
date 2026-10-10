# frozen_string_literal: true

require_relative 'analysis'

module Lungful
  # The printed report, and the script with breath marks added.
  module Report
    module_function

    def clock(seconds)
      s = seconds.round
      format('%<m>d:%<s>02d', m: s / 60, s: s % 60)
    end

    def verdict(target, seconds)
      return '' unless target

      diff = (seconds - target) / target.to_f
      return 'on time' if diff.abs <= 0.10
      return format('%+d%% too long, cut about %d words', (diff * 100).round, words_to_cut(seconds - target)) if diff.positive?

      format('%+d%% short, room for about %d more words', (diff * 100).round, words_to_cut(target - seconds))
    end

    # At about 1.4 syllables per English word.
    def words_to_cut(seconds)
      (seconds * 2.7).round
    end

    # Returns [text, problems]. A problem is a section off its target by more than 10%,
    # or a stretch with nowhere to breathe.
    def render(result, name)
      out = []
      problems = 0
      out << "LUNGFUL  #{name}"
      out << format('Speaking at %.1f syllables a second; a breath every %d syllables at most', result.rate, result.limit)
      out << ''
      width = [result.sections.map { |s| s.title.length }.max, 7].max
      out << format("%-#{width}s  %6s  %8s", 'Section', 'Target', 'Estimate')
      total = 0.0
      total_target = 0
      result.sections.each do |s|
        total += s.seconds
        total_target += s.target.to_i
        v = verdict(s.target, s.seconds)
        problems += 1 if s.target && v != 'on time'
        out << format("%-#{width}s  %6s  %8s   %s", s.title, s.target ? clock(s.target) : '-', clock(s.seconds), v).rstrip
      end
      out << format("%-#{width}s  %6s  %8s", 'Total', total_target.positive? ? clock(total_target) : '-', clock(total))

      unless result.breaths.empty?
        groups = result.breaths.group_by { |b| b.phrase.object_id }.values
        out << ''
        out << "BREATHE HERE  (#{groups.length} stretch#{groups.length == 1 ? '' : 'es'} too long to say in one breath)"
        groups.each do |group|
          b = group.first
          words = b.phrase.words.map(&:text)
          cuts = group.map(&:before_index)
          first = cuts.first
          context = [*words[[0, first - 5].max...first], '/', *words[first, 5]].join(' ')
          out << "  #{b.section}, paragraph #{b.paragraph}: \"...#{context}...\""
          out << "    #{b.syllables} syllables with no comma or full stop. Breathe before " +
                 cuts.map { |i| "\"#{words[i]}\"" }.join(', ') + '.'
        end
        problems += groups.length
      end

      unless result.tricky.empty?
        out << ''
        out << 'TRICKY TO SAY'
        result.tricky.each { |t| out << "  #{t.section}: \"#{t.text}\" #{t.detail}" }
      end
      out << ''
      out << (problems.zero? ? 'Ready to record.' : "#{problems} thing#{problems == 1 ? '' : 's'} to fix before recording.")
      [out.join("\n") + "\n", problems]
    end

    # The script's spoken words with " / " at each suggested breath, paragraph by paragraph.
    def marked(sections, result)
      by_phrase = result.breaths.group_by { |b| b.phrase.object_id }
      out = []
      sections.each do |section|
        out << "## #{section.title}"
        section.paragraphs.each do |phrases|
          line = phrases.map do |p|
            cuts = (by_phrase[p.object_id] || []).map(&:before_index)
            words = p.words.each_with_index.map { |w, i| cuts.include?(i) ? "/ #{w.text}" : w.text }
            words.join(' ') + (p.pause >= 0.6 ? '.' : ',')
          end
          out << line.join(' ')
        end
        out << ''
      end
      out.join("\n")
    end
  end
end
