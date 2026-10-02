require File.expand_path(File.dirname(__FILE__)) + '/../../test_helper'

require 'holidays/date_calculator/hebrew_date.rb'

class HebrewDateCalculatorTests < Test::Unit::TestCase
  def setup
    @subject = Holidays::DateCalculator::HebrewDate.new
  end

  def test_to_gregorian_converts_known_reference_dates
    assert_equal '2023-09-16', @subject.to_gregorian(5784, :tishrei, 1).to_s
    assert_equal '2023-09-25', @subject.to_gregorian(5784, :tishrei, 10).to_s
    assert_equal '2024-03-23', @subject.to_gregorian(5784, :adar_ii, 14).to_s
    assert_equal '2024-04-08', @subject.to_gregorian(5784, :nissan, 1).to_s
    assert_equal '2025-03-13', @subject.to_gregorian(5785, :adar, 14).to_s
    assert_equal '2026-03-02', @subject.to_gregorian(5786, :adar, 14).to_s
    assert_equal '2027-03-20', @subject.to_gregorian(5787, :adar_ii, 14).to_s
  end

  def test_from_gregorian_converts_known_reference_dates
    assert_equal [5784, :tishrei, 1], @subject.from_gregorian(Date.new(2023, 9, 16))
    assert_equal [5784, :tishrei, 10], @subject.from_gregorian(Date.new(2023, 9, 25))
    assert_equal [5784, :adar_ii, 14], @subject.from_gregorian(Date.new(2024, 3, 23))
    assert_equal [5784, :nissan, 1], @subject.from_gregorian(Date.new(2024, 4, 8))
    assert_equal [5785, :adar, 14], @subject.from_gregorian(Date.new(2025, 3, 13))
    assert_equal [5787, :adar_ii, 14], @subject.from_gregorian(Date.new(2027, 3, 20))
  end

  def test_dates_round_trip_across_common_and_leap_years
    [5783, 5784, 5785, 5786, 5787, 5788].each do |year|
      months = @subject.send(:year_months, year)

      months.each do |month|
        @subject.send(:month_length, month, year).times do |offset|
          day = offset + 1
          date = @subject.to_gregorian(year, month, day)
          assert_equal [year, month, day], @subject.from_gregorian(date)
        end
      end
    end
  end

  def test_metonic_cycle_contains_235_months
    leap_years = (5781...5800).count { |year| @subject.send(:leap_year?, year) }
    assert_equal 7, leap_years
    assert_equal 235, (12 * 19) + leap_years
  end

  def test_gregorian_year_occurrence_checks_both_intersecting_hebrew_years
    assert_equal '2023-09-16', @subject.gregorian_year_occurrence(2023, :tishrei, 1).to_s
    assert_equal '2024-04-08', @subject.gregorian_year_occurrence(2024, :nissan, 1).to_s
    assert_equal '2024-03-23', @subject.gregorian_year_occurrence(2024, :adar_ii, 14).to_s
    assert_equal '2025-03-13', @subject.gregorian_year_occurrence(2025, :adar, 14).to_s
    assert_nil @subject.gregorian_year_occurrence(2025, :adar_i, 14)
  end

  def test_accepts_common_month_and_month_aliases
    expected = @subject.to_gregorian(5785, :adar, 14)
    assert_equal expected, @subject.to_gregorian(5785, 12, 14)
    assert_equal expected, @subject.to_gregorian(5785, 'Adar', 14)
    assert_equal @subject.to_gregorian(5784, :adar_i, 14), @subject.to_gregorian(5784, 'Adar I', 14)
    assert_equal @subject.to_gregorian(5784, :adar_i, 14), @subject.to_gregorian(5784, 12, 14)
    assert_equal @subject.to_gregorian(5784, :adar_ii, 14), @subject.to_gregorian(5784, 13, 14)
  end

  def test_invalid_month_raises_readable_error
    error = assert_raise(ArgumentError) { @subject.to_gregorian(5784, :veadar, 1) }
    assert_match(/unknown Hebrew month/, error.message)
    assert_match(/adar_ii/, error.message)
  end

  def test_explicit_adar_names_are_required_in_leap_and_common_years
    error = assert_raise(ArgumentError) { @subject.to_gregorian(5784, :adar, 14) }
    assert_equal 'Adar does not exist in leap Hebrew year 5784; use adar_i or adar_ii', error.message

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :adar_i, 14) }
    assert_equal ':adar_i does not exist in common Hebrew year 5785; use adar', error.message
  end

  def test_invalid_day_raises_readable_error
    assert_raise_message('day 31 does not exist in nissan') { @subject.to_gregorian(5784, :nissan, 31) }
    assert_raise_message('day 30 does not exist in adar ii') { @subject.to_gregorian(5784, :adar_ii, 30) }
  end

  def test_variable_short_month_day_can_exist_but_not_in_that_year
    assert_equal Date.new(2024, 12, 1), @subject.to_gregorian(5785, :cheshvan, 29)
    assert_equal Date.new(2024, 12, 2), @subject.to_gregorian(5785, :kislev, 1)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :cheshvan, 30) }
    assert_equal 'day 30 does not exist in cheshvan 5785', error.message
  end
end
