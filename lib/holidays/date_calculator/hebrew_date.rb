require 'date'

module Holidays
  module DateCalculator
    # Arithmetic Hebrew (Anno Mundi) calendar.
    #
    # The calendar is based on the 19-year leap cycle, the traditional mean
    # lunation (29 days, 12 hours, 793 parts), and the four Rosh Hashanah
    # postponement rules. It converts whole civil dates only; it does not model
    # sunset or any observational correction.
    class HebrewDate
      EPOCH_JDN = 347_998

      MONTH_ALIASES = {
        nissan: :nissan,
        iyyar: :iyyar,
        iyar: :iyyar,
        sivan: :sivan,
        tammuz: :tammuz,
        tamuz: :tammuz,
        av: :av,
        elul: :elul,
        tishrei: :tishrei,
        tishri: :tishrei,
        cheshvan: :cheshvan,
        marheshvan: :cheshvan,
        marcheshvan: :cheshvan,
        kislev: :kislev,
        chislev: :kislev,
        tevet: :tevet,
        tebet: :tevet,
        shevat: :shevat,
        shebat: :shevat,
        adar: :adar,
        adar_i: :adar_i,
        adar_1: :adar_i,
        adar_2: :adar_ii,
        adar_ii: :adar_ii,
      }.freeze

      MONTH_NAMES = %i[
        nissan iyyar sivan tammuz av elul tishrei cheshvan kislev tevet
        shevat adar adar_i adar_ii
      ].freeze

      def to_gregorian(year, month, day)
        month = canonical_month(month, year)
        validate_date!(year, month, day)
        Date.jd(to_jd(year, month, day))
      end

      def from_gregorian(date)
        date = Date.new(date.year, date.month, date.day)
        jdn = date.jd

        year = (((jdn - EPOCH_JDN) / 365.2468222).floor + 2).to_i
        year -= 1 while jdn < rosh_hashanah_jdn(year)
        year += 1 while jdn >= rosh_hashanah_jdn(year + 1)

        months = year_months(year)
        month_start = rosh_hashanah_jdn(year)

        months.each do |month|
          length = month_length(month, year)
          if jdn < month_start + length
            return [year, month, jdn - month_start + 1]
          end

          month_start += length
        end
      end

      # Return the occurrence of a fixed Hebrew date within a Gregorian year,
      # or nil when that named month does not occur (for example, Adar I in a
      # common Hebrew year). Every Gregorian year intersects two Hebrew years,
      # so check the nearby Hebrew years instead of mapping one Gregorian year
      # to a single Hebrew year.
      def gregorian_year_occurrence(gregorian_year, month, day)
        month = canonical_month(month)
        validate_rule_day!(month, day)

        (gregorian_year + 3759..gregorian_year + 3762).each do |hebrew_year|
          next unless month_exists_in_year?(month, hebrew_year)

          begin
            date = Date.jd(to_jd(hebrew_year, month, day))
          rescue ArgumentError
            next
          end

          return date if date.year == gregorian_year
        end

        nil
      end


      # Validate a month/day pair without knowing whether variable months such as
      # Cheshvan/Kislev have 29 or 30 days in that particular year.
      def validate_rule!(month, day)
        month = canonical_month(month)
        validate_rule_day!(month, day)
        month
      end

      private

      def leap_year?(year)
        ((7 * year) + 1) % 19 < 7
      end

      def year_length(year)
        rosh_hashanah_jdn(year + 1) - rosh_hashanah_jdn(year)
      end

      def rosh_hashanah_jdn(year)
        months = (235 * year - 234) / 19
        parts = 204 + 765_433 * months
        days = parts / 25_920
        remainder = parts % 25_920
        weekday = days % 7

        case weekday
        when 3, 4, 5
          days += 1
        when 6
          days += 1 if leap_year?(year)
        end

        # The remaining two postponements are applied to the molad's weekday
        # before Lo ADU, so the condition is offset from the final JDN weekday.
        if weekday == 2 && !leap_year?(year) && leap_year?(year - 1)
          days += 1
        elsif weekday == 1
          days += 1
        elsif weekday == 2 && !leap_year?(year) && remainder >= 15_824
          days += 2
        elsif weekday == 1 && leap_year?(year - 1) && remainder >= 9_924
          days += 2
        end

        EPOCH_JDN + days
      end

      def year_months(year)
        if leap_year?(year)
          %i[tishrei cheshvan kislev tevet shevat adar_i adar_ii nissan iyyar sivan tammuz av elul]
        else
          %i[tishrei cheshvan kislev tevet shevat adar nissan iyyar sivan tammuz av elul]
        end
      end

      def month_exists_in_year?(month, year)
        case month
        when :adar
          !leap_year?(year)
        when :adar_i, :adar_ii
          leap_year?(year)
        else
          year >= 1
        end
      end

      def month_length(month, year)
        case month
        when :iyyar, :tammuz, :elul, :tevet, :adar_ii
          29
        when :nissan, :sivan, :av, :tishrei, :shevat
          30
        when :kislev
          leap_year?(year) ? (year_length(year) == 385 ? 30 : 29) : (year_length(year) == 354 ? 30 : 29)
        when :adar_i
          year_length(year) == 385 ? 30 : 29
        when :adar
          year_length(year) == 355 ? 30 : 29
        when :cheshvan
          leap_year?(year) ? (year_length(year) % 10 == 5 ? 30 : 29) : (year_length(year) == 355 ? 30 : 29)
        end
      end

      def to_jd(year, month, day)
        validate_date!(year, month, day)

        jdn = rosh_hashanah_jdn(year) + day - 1

        year_months(year).take_while { |candidate| candidate != month }.each do |candidate|
          jdn += month_length(candidate, year)
        end

        jdn
      end

      def canonical_month(month, year = nil)
        case month
        when Integer
          canonical = integer_month(month, year)
        when Symbol, String
          normalized = month.to_s.downcase.tr('-', '_').gsub(/\s+/, '_')
          normalized = "adar_#{roman_number(normalized)}" if %w[i ii].include?(normalized)
          canonical = MONTH_ALIASES[normalized.to_sym]
        end

        return canonical if canonical

        valid = MONTH_NAMES.map(&:to_s).join(', ')
        raise ArgumentError, "unknown Hebrew month #{month.inspect}; valid months are: #{valid}"
      end

      def roman_number(month)
        month == 'i' ? 'i' : 'ii'
      end

      def integer_month(month, year)
        case month
        when 1..6
          %i[nissan iyyar sivan tammuz av elul][month - 1]
        when 7..11
          %i[tishrei cheshvan kislev tevet shevat][month - 7]
        when 12
          year.nil? || leap_year?(year) ? :adar_i : :adar
        when 13
          :adar_ii
        end
      end

      def validate_date!(year, month, day)
        unless year.is_a?(Integer) && year >= 1
          raise ArgumentError, "Hebrew year must be an integer greater than or equal to 1"
        end

        unless month_exists_in_year?(month, year)
          if leap_year?(year)
            raise ArgumentError, "Adar does not exist in leap Hebrew year #{year}; use adar_i or adar_ii"
          else
            raise ArgumentError, "#{month.inspect} does not exist in common Hebrew year #{year}; use adar"
          end
        end

        validate_day_of_month!(month, day)

        if day > month_length(month, year)
          raise ArgumentError, "day #{day} does not exist in #{month_name(month)} #{year}"
        end
      end

      def validate_day_of_month!(month, day)
        unless day.is_a?(Integer) && day >= 1
          raise ArgumentError, "Hebrew day must be an integer greater than or equal to 1"
        end

        max_day = %i[cheshvan kislev adar].include?(month) ? 30 : month_length_without_year(month)
        if day > max_day
          raise ArgumentError, "day #{day} does not exist in #{month_name(month)}"
        end
      end

      def validate_rule_day!(month, day)
        unless day.is_a?(Integer) && day >= 1
          raise ArgumentError, "Hebrew day must be an integer greater than or equal to 1"
        end

        max_day = %i[cheshvan kislev adar_i].include?(month) ? 30 : 29
        return if day <= max_day

        raise ArgumentError, "day #{day} does not exist in #{month_name(month)}"
      end

      def month_length_without_year(month)
        { adar_i: 30, adar_ii: 29 }.fetch(month) { month_length(month, 1) }
      end

      def month_name(month)
        month.to_s.tr('_', ' ')
      end
    end
  end
end
