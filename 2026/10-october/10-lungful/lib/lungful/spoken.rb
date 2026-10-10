# frozen_string_literal: true

module Lungful
  # How long words take to say: syllables in ordinary words, and what numbers,
  # money, percentages and acronyms turn into when they are read aloud.
  module Spoken
    ONES = %w[zero one two three four five six seven eight nine ten eleven twelve thirteen
              fourteen fifteen sixteen seventeen eighteen nineteen].freeze
    TENS = %w[_ _ twenty thirty forty fifty sixty seventy eighty ninety].freeze

    # Words the vowel-group rule gets wrong, with their real syllable counts.
    EXCEPTIONS = {
      'people' => 2, 'every' => 3, 'business' => 2, 'different' => 3, 'evening' => 3,
      'area' => 3, 'idea' => 3, 'media' => 3, 'video' => 3, 'radio' => 3, 'science' => 2,
      'quiet' => 2, 'create' => 2, 'created' => 3, 'being' => 2, 'going' => 2,
      'doing' => 2, 'seeing' => 2, 'real' => 1, 'really' => 2, 'eye' => 1, 'eyes' => 1,
      'once' => 1, 'one' => 1, 'are' => 1, 'were' => 1, 'there' => 1, 'where' => 1,
      'here' => 1, 'come' => 1, 'some' => 1, 'done' => 1, 'gone' => 1, 'none' => 1,
      'whole' => 1, 'sure' => 1, 'australia' => 4, 'australian' => 4, 'diabetes' => 4,
      'anaemia' => 4, 'anemia' => 4, 'pharmacy' => 3, 'pharmacist' => 3, 'medicine' => 3,
      'algorithm' => 4, 'average' => 3, 'favourite' => 3, 'favorite' => 3, 'family' => 3,
      'interest' => 3, 'interesting' => 4, 'naturally' => 4, 'actually' => 4,
      'usually' => 4, 'probably' => 3, 'poem' => 2, 'ruin' => 2, 'lion' => 2,
      'beautiful' => 3, 'because' => 2, 'something' => 2, 'sometimes' => 2
    }.freeze

    # Letter names, for acronyms that are spelled out: "W" alone is three syllables.
    LETTER_SYLLABLES = Hash.new(1).merge('W' => 3).freeze

    module_function

    # Syllables in one ordinary English word, by counting vowel groups with the usual fixes.
    def syllables(word)
      w = word.downcase.delete("^a-z")
      return 0 if w.empty?
      return EXCEPTIONS[w] if EXCEPTIONS.key?(w)
      return 1 if w.length <= 3

      w = w.sub(/(?:[^laeiouy]es|[^laeiouy]ed|[^laeiouy]e)\z/, '') # silent e: make, hoped, takes
      w = w.sub(/\Ay/, '') # a leading y is a consonant: yes, young
      count = w.scan(/[aeiouy]{1,2}/).length
      count.clamp(1, 12)
    end

    # Whole numbers in words: 2021 -> "two thousand and twenty-one".
    def number_words(n)
      return ONES[n] if n < 20
      return (n % 10).zero? ? TENS[n / 10] : "#{TENS[n / 10]}-#{ONES[n % 10]}" if n < 100
      return "#{ONES[n / 100]} hundred#{(n % 100).zero? ? '' : " and #{number_words(n % 100)}"}" if n < 1000

      [[1_000_000_000, 'billion'], [1_000_000, 'million'], [1000, 'thousand']].each do |size, name|
        next if n < size

        rest = n % size
        joiner = rest.positive? && rest < 100 ? ' and ' : ' '
        return "#{number_words(n / size)} #{name}#{rest.zero? ? '' : joiner + number_words(rest)}"
      end
    end

    # Years are read in pairs: 1998 -> "nineteen ninety-eight", 2021 -> "twenty twenty-one".
    def year_words(n)
      return number_words(n) if (2000..2009).cover?(n)

      high = n / 100
      low = n % 100
      tail = if low.zero? then 'hundred'
             elsif low < 10 then "oh #{ONES[low]}"
             else number_words(low)
             end
      "#{number_words(high)} #{tail}"
    end

    NUMBER = /\A(\$)?(\d{1,3}(?:,\d{3})+|\d+)(?:\.(\d{1,2}))?(%)?\z/

    # What a token sounds like, as words, or nil if it's an ordinary word.
    # "222,475" -> "two hundred and twenty-two thousand four hundred and seventy-five".
    def expand(token)
      if (m = NUMBER.match(token))
        digits = m[2].delete(',')
        return nil if digits.length > 12

        n = digits.to_i
        words = if m[1].nil? && m[3].nil? && m[4].nil? && digits.length == 4 && (1100..2099).cover?(n)
                  year_words(n)
                else
                  number_words(n)
                end
        if m[3]
          words += m[1] ? " dollars #{number_words(m[3].ljust(2, '0').to_i)}" : " point #{m[3].chars.map { |d| ONES[d.to_i] }.join(' ')}"
        elsif m[1]
          words += n == 1 ? ' dollar' : ' dollars'
        end
        words += ' per cent' if m[4]
        return words
      end
      # Short all-capital acronyms are spelled out: ABS -> "A B S". Longer ones are said as words.
      return token.chars.join(' ') if token.match?(/\A[A-Z]{2,3}s?\z/)

      nil
    end

    # Syllables for any token, expanding numbers and acronyms first.
    def token_syllables(token)
      spoken = expand(token)
      return syllables(token) if spoken.nil?
      return token.delete('s').chars.sum { |c| LETTER_SYLLABLES[c] } if token.match?(/\A[A-Z]{2,3}s?\z/)

      spoken.split(/[ -]/).sum { |w| syllables(w) }
    end
  end
end
