module Holidays
  module Definition
    module CustomMethods
      # il custom holiday calculations.
      #
      # These dates are fixed in the arithmetic Hebrew calendar
      # (Holidays::DateCalculator::HebrewDate). The finder calls month-0
      # rules once per Gregorian year, and the calculator inspects *both*
      # Hebrew years overlapping that Gregorian year, so a range query
      # crossing the Tishrei boundary resolves correctly instead of mapping
      # the Gregorian year to a single Hebrew year.
      module IL
        class << self
          # 1 Tishrei
          def jewish_new_year(year)
            hebrew.gregorian_year_occurrence(year, :tishrei, 1)
          end

          # 2 Tishrei
          def second_new_year_day(year)
            hebrew.gregorian_year_occurrence(year, :tishrei, 2)
          end

          # 10 Tishrei
          def day_of_atonement(year)
            hebrew.gregorian_year_occurrence(year, :tishrei, 10)
          end

          # 15 Tishrei
          def feast_of_tabernacles(year)
            hebrew.gregorian_year_occurrence(year, :tishrei, 15)
          end

          # 23 Tishrei (Simchat Torah / Shemini Atzeret second day)
          def rejoicing_of_the_torah(year)
            hebrew.gregorian_year_occurrence(year, :tishrei, 23)
          end

          # 13 Adar in a common year, 13 Adar II in a leap year (the Fast of
          # Esther sits one day before Purim, which is always in Adar II).
          def exodus_from_egypt(year)
            hebrew.gregorian_year_occurrence(year, :adar, 13)
          end

          # 19 Adar/Adar II.
          def exodus_from_egypt_day_7(year)
            hebrew.gregorian_year_occurrence(year, :adar, 19)
          end

          private

          def hebrew
            Holidays::Factory::DateCalculator.hebrew_date
          end
        end
      end
    end
  end
end
