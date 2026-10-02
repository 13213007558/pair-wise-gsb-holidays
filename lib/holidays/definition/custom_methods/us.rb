require 'date'

module Holidays
  module Definition
    module CustomMethods
      # us custom holiday calculations, ported verbatim from the
      # +methods:+ block in definitions/us.yaml.
      module US
        class << self
          def christmas_eve_holiday(date)
            beginning_of_month = Date.civil(date.year, date.month, 1)
            (date.saturday? || date.sunday?) ? date.downto(beginning_of_month).find {|d| d if d.wday == 5} : date
          end

          def rosh_hashanah(year)
            Holidays::Factory::DateCalculator.hebrew_date.gregorian_year_occurrence(year, :tishrei, 1)
          end

          def yom_kippur(year)
            Holidays::Factory::DateCalculator.hebrew_date.gregorian_year_occurrence(year, :tishrei, 10)
          end

          def georgia_state_holiday(year, month)
            beginning_of_month = Date.civil(year, month, 1)
            state_holiday = Date.civil(year, month, 26)
            state_holiday.downto(beginning_of_month).find {|date| date if date.wday == 1 }
          end

          def lee_jackson_day(year, month)
            day_of_holiday = Holidays::Factory::DateCalculator.day_of_month_calculator.call(year, month, 3, 1)
            beginning_of_month = Date.civil(year, month, 1)
            king_day = Date.civil(year, month, day_of_holiday)
            king_day.downto(beginning_of_month).find {|date| date if date.wday == 5 }
          end

          def juneteenth_national_independence_day(region, date)
            if region == :us_ut
              case date.wday
              when 1
                date
              when 2,3,4,5
                date - (date.wday - 1)
              when 6
                date + 2
              when 0
                date + 1
              end
            elsif date.wday == 0
              date + 1
            elsif date.wday == 6
              date - 1
            else
              date
            end
          end

          # Independence Day observed shift, which varies by region:
          #   - us_ri: Rhode Island moves to the following Monday on a weekend
          #     (Saturday -> +2, Sunday -> +1).
          #   - us_tx: Texas does not shift, the date is returned unchanged.
          #   - everyone else: nearest weekday, same as +to_weekday_if_weekend+
          #     (Saturday -> Friday, Sunday -> Monday).
          def independence_day(region, date)
            if region == :us_ri
              case date.wday
              when 6
                date + 2
              when 0
                date + 1
              else
                date
              end
            elsif region == :us_tx
              date
            elsif date.wday == 6
              date - 1
            elsif date.wday == 0
              date + 1
            else
              date
            end
          end

          def election_day(year)
            Holidays::Factory::DateCalculator.day_of_month_calculator.call(year, 11, 1, 1) + 1
          end

          def even_year_election_day(year)
            if year % 2 == 0
              Holidays::Factory::DateCalculator.day_of_month_calculator.call(year, 11, 1, 1) + 1
            end
          end

          def us_inauguration_day(year)
            year % 4 == 1 ? 20 : nil
          end
        end
      end
    end
  end
end
