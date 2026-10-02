require 'date'

module Holidays
  module DateCalculator
    # Arithmetic Hebrew calendar ("fixed" calendar attributed to Hillel II,
    # 4th century CE). Purely arithmetic: the 19-year leap cycle, the four
    # Rosh Hashanah postponements (dehiyyot), and year-type-dependent lengths
    # for Marcheshvan and Kislev. No sunset estimation, no astronomical or
    # network lookup; a holiday that begins at sunset is represented by its
    # first full civil day.
    #
    # Months are referenced by an unambiguous symbol (preferred) or by the
    # fixed integer numbering, which counts from Tishrei and renames Adar in
    # leap years so the numbering itself never shifts:
    #
    #   1 Tishrei (Rosh Hashanah)
    #   2 Marcheshvan (Cheshvan)
    #   3 Kislev
    #   4 Tevet
    #   5 Shevat
    #   6 Adar (common year) / Adar I (leap year)
    #   7 Adar II (leap year only)
    #   8 Nisan
    #   9 Iyyar
    #  10 Sivan
    #  11 Tammuz
    #  12 Av
    #  13 Elul
    #
    # In a common year :adar is the single Adar (month 6). In a leap year
    # that name is ambiguous and callers must use :adar_i or :adar_ii.
    # Asking for a month that does not exist in the target year, or a day
    # outside the month, raises ArgumentError with a readable message.
    class HebrewDate
      HebrewCalendarDate = Struct.new(:year, :month, :day) do
        def month_name
          HebrewDate.month_name_for(year, month)
        end
      end

      MONTH_NAMES = [
        nil,
        'Tishrei',
        'Marcheshvan',
        'Kislev',
        'Tevet',
        'Shevat',
        'Adar',
        'Adar II',
        'Nisan',
        'Iyyar',
        'Sivan',
        'Tammuz',
        'Av',
        'Elul',
      ].freeze

      MONTH_ALIASES = {
        :tishrei => 1, :tishri => 1,
        :marcheshvan => 2, :cheshvan => 2, :heshvan => 2,
        :kislev => 3,
        :tevet => 4,
        :shevat => 5, :shvat => 5, :shebat => 5,
        :adar_i => 6, :adari => 6, :adar1 => 6, :adar_1 => 6,
        :adar_ii => 7, :adarii => 7, :adar2 => 7, :adar_2 => 7,
        :nisan => 8,
        :iyyar => 9, :iyar => 9,
        :sivan => 10,
        :tammuz => 11, :tamuz => 11,
        :av => 12,
        :elul => 13,
      }.freeze

      class << self
        def month_name_for(year, month)
          if month == 6 && new.leap_year?(year)
            'Adar I'
          else
            MONTH_NAMES[month]
          end
        end
      end

      def to_gregorian(hebrew_year, hebrew_month, hebrew_day)
        Date.jd(to_jdn(hebrew_year, hebrew_month, hebrew_day))
      end

      def to_hebrew(date)
        jdn = date.jd
        # Initial year estimate from the mean length of a Hebrew year
        # (6939.7/19 days), scaled to integer arithmetic. It is an
        # approximation; the two correction walks below converge on the
        # exact Hebrew year.
        year = [1, (190 * (jdn - JDN_OFFSET)) / 69_397].max
        year += 1 while rosh_hashanah_jdn(year + 1) <= jdn
        year -= 1 while year > 1 && rosh_hashanah_jdn(year) > jdn

        day_of_year = jdn - rosh_hashanah_jdn(year) + 1
        ordered_months(year).each do |month|
          length = month_length(year, month)
          if day_of_year <= length
            return HebrewCalendarDate.new(year, month, day_of_year)
          end
          day_of_year -= length
        end
      end

      # Given a Gregorian year and a fixed Hebrew month/day, return the
      # occurrence that falls within that Gregorian year, or nil if none does.
      #
      # A Gregorian year always overlaps parts of two Hebrew years, so a
      # caller cannot map the Gregorian year to one Hebrew year and run the
      # formula a single time. The Hebrew year whose Tishrei starts in
      # Gregorian year Y is Y + 3761; the two overlapping Hebrew years cover
      # every month bucket of Y.
      #
      # The unqualified :adar means Adar in a common year and Adar II in a
      # leap year (the month in which Purim falls). Explicit :adar_i or
      # :adar_ii selects a specific Adar and may skip a Hebrew year in which
      # that month does not exist.
      def gregorian_year_occurrence(gregorian_year, hebrew_month, hebrew_day)
        [gregorian_year + 3760, gregorian_year + 3761].each do |hebrew_year|
          month = resolve_month_skipping_absent(hebrew_year, hebrew_month)
          next unless month
          next unless hebrew_day.between?(1, month_length(hebrew_year, month))

          date = to_gregorian(hebrew_year, month, hebrew_day)
          return date if date.year == gregorian_year
        end

        nil
      end

      def leap_year?(year)
        (7 * year + 1) % 19 < 7
      end

      def months_in_year(year)
        leap_year?(year) ? 13 : 12
      end

      def days_in_year(year)
        rosh_hashanah_jdn(year + 1) - rosh_hashanah_jdn(year)
      end

      def month_name(year, month)
        self.class.month_name_for(year, resolve_month(year, month))
      end

      private

      # Mean synodic month: 29 days, 12 hours, 793 parts (halakim). A part
      # is 1/1080 of an hour; a day has 25,920 parts.
      PARTS_PER_DAY = 25_920
      PARTS_PER_HOUR = 1_080
      MOLAD_PARTS = 29 * PARTS_PER_DAY + 12 * PARTS_PER_HOUR + 793

      # Molad Tishrei of year 1 (BeHaRaD): Monday, 5 hours, 204 parts, with
      # Monday counted as weekday 0.
      BAHARAD = 5 * PARTS_PER_HOUR + 204

      # JDN of molad day index 0, fixed so that Rosh Hashanah 5784 is
      # 2023-09-16 (Julian day number 2460204).
      JDN_OFFSET = 347_998

      # Months from before year 1 through the last month preceding +year+
      # (Adar in common years, Adar II in leap years): 235 per complete
      # 19-year cycle (125 common months plus 7 leap years of 13).
      def months_elapsed(year)
        completed = year - 1
        complete_cycles, remainder = completed.divmod(19)
        235 * complete_cycles + 12 * remainder + (7 * remainder + 1) / 19
      end

      # Julian day number of 1 Tishrei of +year+, applying the four
      # postponements in order:
      #   Molad Zaken   - molad at or after 18:00 pushes to the next day
      #   GaTaRad       - common year starting Tuesday with a late molad: +2
      #   BeTU-TQaFot   - year after a leap year starting Monday with a late
      #                   molad: +1
      #   Lo ADU        - Rosh Hashanah never falls Sunday/Wednesday/Friday
      # The special rules are evaluated against the unadjusted molad; Lo ADU
      # is re-applied after a shift. Weekday 0 is Monday, so the forbidden
      # weekdays are 2 (Wednesday), 4 (Friday) and 6 (Sunday).
      def rosh_hashanah_jdn(year)
        molad = BAHARAD + months_elapsed(year) * MOLAD_PARTS
        day, parts = molad.divmod(PARTS_PER_DAY)
        weekday = day % 7

        if weekday == 1 && !leap_year?(year) && parts >= 9 * PARTS_PER_HOUR + 204
          day += 2
        elsif weekday == 0 && leap_year?(year - 1) && parts >= 15 * PARTS_PER_HOUR + 589
          day += 1
        elsif parts >= 18 * PARTS_PER_HOUR
          day += 1
        end

        day += 1 if [2, 4, 6].include?(day % 7)

        day + JDN_OFFSET
      end

      def ordered_months(year)
        leap_year?(year) ? (1..13).to_a : (1..13).to_a - [7]
      end

      def month_exists?(year, month)
        ordered_months(year).include?(month)
      end

      # Fixed months follow the 30/29 alternation; Marcheshvan (2) and
      # Kislev (3) vary with the six permitted year lengths (353/354/355
      # for common years, 383/384/385 for leap years); Adar I (6) exists
      # only in leap years with 30 days, Adar II (7) always has 29.
      def month_length(year, month)
        case month
        when 2
          [355, 385].include?(days_in_year(year)) ? 30 : 29
        when 3
          [353, 383].include?(days_in_year(year)) ? 29 : 30
        when 6
          leap_year?(year) ? 30 : 29
        when 7
          29
        when 1, 5, 8, 10, 12
          30
        else
          29
        end
      end

      def resolve_month(year, month)
        if month == :adar
          if leap_year?(year)
            raise ArgumentError, 'month :adar is ambiguous in a leap year; use :adar_i or :adar_ii'
          end
          month = 6
        elsif month.is_a?(Symbol)
          month = MONTH_ALIASES.fetch(month) do
            raise ArgumentError, "unknown Hebrew month #{month.inspect}; expected a month symbol (e.g. :nisan)"
          end
        end

        unless month.is_a?(Integer) && month.between?(1, 13)
          raise ArgumentError, "unknown Hebrew month #{month.inspect}; expected 1-13 or a month symbol (e.g. :nisan)"
        end
        unless month_exists?(year, month)
          raise ArgumentError, "Adar II (month 7) does not exist in common Hebrew year #{year}; use month 6 for Adar"
        end

        month
      end

      # Like resolve_month, but a month absent in this particular Hebrew year
      # (a specific Adar in the wrong year kind) means this candidate year
      # contributes no occurrence, so the lookup skips it instead of raising.
      def resolve_month_skipping_absent(year, month)
        return 7 if month == :adar && leap_year?(year)
        return 6 if month == :adar
        if month == :adar_i
          return leap_year?(year) ? 6 : nil
        end
        month = MONTH_ALIASES.fetch(month, month) if month.is_a?(Symbol)
        return unless month.is_a?(Integer) && month.between?(1, 13)
        return unless month_exists?(year, month)
        month
      end

      def to_jdn(year, month, day)
        month = resolve_month(year, month)
        length = month_length(year, month)
        unless day.between?(1, length)
          raise ArgumentError, "day #{day} does not exist in #{self.class.month_name_for(year, month)} #{year}; that month has #{length} days"
        end

        jdn = rosh_hashanah_jdn(year) + day - 1
        ordered_months(year).each do |prior_month|
          break if prior_month == month
          jdn += month_length(year, prior_month)
        end
        jdn
      end
    end
  end
end
