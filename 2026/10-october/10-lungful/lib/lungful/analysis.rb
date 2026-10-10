# frozen_string_literal: true

require_relative 'script'

module Lungful
  # Turns a parsed script into timings, breath points and tricky spots.
  module Analysis
    # Words a phrase can be split before without changing its meaning: the joints of a sentence.
    JOINTS = %w[and but or so because which who whom whose that when while where although though
                if unless until since after before as with without for to from by than then].freeze

    SectionReport = Struct.new(:title, :target, :seconds, :syllables, keyword_init: true)
    Breath = Struct.new(:section, :paragraph, :phrase, :before_index, :syllables, keyword_init: true)
    Tricky = Struct.new(:section, :kind, :text, :detail, keyword_init: true)
    Result = Struct.new(:sections, :breaths, :tricky, :rate, :limit, keyword_init: true)

    module_function

    # rate: syllables spoken per second. limit: most syllables comfortable in one breath.
    def run(sections, rate:, limit:)
      reports = []
      breaths = []
      tricky = []
      sections.each do |section|
        syl = 0
        pauses = 0.0
        section.paragraphs.each_with_index do |phrases, pi|
          phrases.each do |phrase|
            syl += phrase.syllables
            pauses += phrase.pause
            split_points(phrase.words, limit).each do |idx|
              breaths << Breath.new(section: section.title, paragraph: pi + 1, phrase: phrase,
                                    before_index: idx, syllables: phrase.syllables)
            end
            tricky.concat(tricky_spots(section.title, phrase))
          end
        end
        reports << SectionReport.new(title: section.title, target: section.target,
                                     seconds: (syl / rate) + pauses, syllables: syl)
      end
      Result.new(sections: reports, breaths: breaths, tricky: tricky.uniq { |t| [t.kind, t.text] }, rate: rate, limit: limit)
    end

    # Where to breathe in a phrase that is too long: the indexes of the words to breathe
    # before. Prefer a joint word near the middle; otherwise the word boundary nearest it.
    # Applied again to each half until every piece fits.
    def split_points(words, limit, offset = 0)
      total = words.sum(&:syllables)
      return [] if total <= limit || words.length < 2

      running = 0
      before = words.map { |w| (running += w.syllables) - w.syllables } # syllables before each word
      candidates = (1...words.length).select { |i| before[i] >= total * 0.3 && before[i] <= total * 0.7 }
      joint = candidates.select { |i| JOINTS.include?(words[i].text.downcase) }
      pool = joint.empty? ? (1...words.length).to_a : joint
      cut = pool.min_by { |i| [(before[i] - (total / 2.0)).abs, i] }
      split_points(words[0...cut], limit, offset) + [offset + cut] + split_points(words[cut..], limit, offset + cut)
    end

    SIBILANT = /\A(s|sh|ch|z)(?=[aeiouy])/i

    # Spots that are hard to say aloud: long numbers, strings of spelled-out acronyms,
    # tongue-twisting runs of s and sh sounds, and very long words.
    def tricky_spots(section, phrase)
      found = []
      phrase.words.each do |w|
        spoken = Spoken.expand(w.text)
        if spoken && w.syllables >= 10 && w.text.match?(/\d/)
          found << Tricky.new(section: section, kind: :number, text: w.text,
                              detail: "#{w.syllables} syllables aloud (\"#{spoken}\"). Try \"about #{rounded(w.text)}\".")
        elsif spoken.nil? && w.syllables >= 6
          found << Tricky.new(section: section, kind: :long_word, text: w.text, detail: "#{w.syllables} syllables in one word")
        end
      end
      acronyms = phrase.words.map(&:text).each_cons(3).find { |run| run.all? { |t| t.match?(/\A[A-Z]{2,3}s?\z/) || t.match?(/\A[\d,.$%]+\z/) } }
      found << Tricky.new(section: section, kind: :pile_up, text: acronyms.join(' '), detail: 'three acronyms or numbers in a row') if acronyms
      sounds = phrase.words.map { |w| w.text[SIBILANT, 1]&.downcase }
      sounds.each_cons(3).with_index do |run, i|
        next unless run.all? && run.uniq.length > 1

        text = phrase.words[i, 3].map(&:text).join(' ')
        found << Tricky.new(section: section, kind: :twister, text: text, detail: 'alternating s and sh sounds (a tongue-twister)')
        break
      end
      found
    end

    # 222,475 -> "220,000"; 1,234,567 -> "1.2 million". Two significant figures.
    def rounded(text)
      digits = text[/[\d,]+/].delete(',')
      n = digits.to_i
      return text if n < 100

      if n >= 1_000_000
        format('%.1f million', (n / 100_000).round / 10.0).sub('.0 ', ' ')
      else
        magnitude = 10**(n.digits.length - 2)
        ((n.to_f / magnitude).round * magnitude).to_s.reverse.scan(/\d{1,3}/).join(',').reverse
      end
    end
  end
end
