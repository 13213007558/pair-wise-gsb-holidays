require File.expand_path(File.dirname(__FILE__)) + '/../../test_helper'

require 'holidays/date_calculator/hebrew_date.rb'

class HebrewDateCalculatorTests < Test::Unit::TestCase
  def setup
    @subject = Holidays::DateCalculator::HebrewDate.new
  end

  # Rosh Hashanah (1 Tishrei), 18 consecutive civil years, cross-checked
  # against published civil-date tables.
  def test_to_gregorian_converts_rosh_hashanah_reference_dates
    {
      5770 => '2009-09-19', 5771 => '2010-09-09', 5772 => '2011-09-29',
      5773 => '2012-09-17', 5774 => '2013-09-05', 5775 => '2014-09-25',
      5776 => '2015-09-14', 5777 => '2016-10-03', 5778 => '2017-09-21',
      5779 => '2018-09-10', 5780 => '2019-09-30', 5781 => '2020-09-19',
      5782 => '2021-09-07', 5783 => '2022-09-26', 5784 => '2023-09-16',
      5785 => '2024-10-03', 5786 => '2025-09-23', 5787 => '2026-09-12',
    }.each do |year, expected|
      assert_equal expected, @subject.to_gregorian(year, :tishrei, 1).to_s
    end
  end

  def test_to_gregorian_converts_fixed_festival_dates
    # Passover (15 Nisan), including common and leap Hebrew years.
    assert_equal '2020-04-09', @subject.to_gregorian(5780, :nisan, 15).to_s
    assert_equal '2022-04-16', @subject.to_gregorian(5782, :nisan, 15).to_s
    assert_equal '2024-04-23', @subject.to_gregorian(5784, :nisan, 15).to_s
    assert_equal '2025-04-13', @subject.to_gregorian(5785, :nisan, 15).to_s
    assert_equal '2026-04-02', @subject.to_gregorian(5786, :nisan, 15).to_s

    # Yom Kippur (10 Tishrei), Sukkot (15), Shemini Atzeret/Simchat Torah (23).
    assert_equal '2024-10-12', @subject.to_gregorian(5785, :tishrei, 10).to_s
    assert_equal '2022-10-10', @subject.to_gregorian(5783, :tishrei, 15).to_s
    assert_equal '2025-10-15', @subject.to_gregorian(5786, :tishrei, 23).to_s

    # Hanukkah (25 Kislev) lands in December of the prior Gregorian year.
    assert_equal '2023-12-08', @subject.to_gregorian(5784, :kislev, 25).to_s
    assert_equal '2024-12-26', @subject.to_gregorian(5785, :kislev, 25).to_s
    assert_equal '2025-12-15', @subject.to_gregorian(5786, :kislev, 25).to_s
  end

  def test_to_gregorian_distinguishes_the_two_adars_in_leap_years
    # 5784 is a leap year: Adar I 14 (Purim Katan area) vs Adar II 14 (Purim).
    assert_equal '2024-02-23', @subject.to_gregorian(5784, :adar_i, 14).to_s
    assert_equal '2024-03-24', @subject.to_gregorian(5784, :adar_ii, 14).to_s

    # 5783/5785 are common: the single Adar uses :adar.
    assert_equal '2023-03-07', @subject.to_gregorian(5783, :adar, 14).to_s
    assert_equal '2025-03-14', @subject.to_gregorian(5785, :adar, 14).to_s

    # Integer numbering: 6 is Adar/Adar I, 7 is Adar II.
    assert_equal '2024-02-23', @subject.to_gregorian(5784, 6, 14).to_s
    assert_equal '2024-03-24', @subject.to_gregorian(5784, 7, 14).to_s
    assert_equal '2023-03-07', @subject.to_gregorian(5783, 6, 14).to_s
  end

  def test_to_hebrew_inverts_to_gregorian_for_every_day_over_many_centuries
    Date.new(100, 1, 1).upto(Date.new(3000, 12, 31)) do |date|
      hebrew = @subject.to_hebrew(date)
      assert_equal date,
                   @subject.to_gregorian(hebrew.year, hebrew.month, hebrew.day),
                   "round trip failed on #{date} -> #{hebrew.year}-#{hebrew.month}-#{hebrew.day}"
    end
  end

  def test_to_hebrew_returns_named_month
    hebrew = @subject.to_hebrew(Date.new(2025, 4, 13))
    assert_equal [5785, 8, 15], [hebrew.year, hebrew.month, hebrew.day]
    assert_equal 'Nisan', hebrew.month_name

    leap = @subject.to_hebrew(Date.new(2024, 3, 24))
    assert_equal [5784, 7, 14], [leap.year, leap.month, leap.day]
    assert_equal 'Adar II', leap.month_name

    adar_i = @subject.to_hebrew(Date.new(2024, 2, 23))
    assert_equal [5784, 6, 14], [adar_i.year, adar_i.month, adar_i.day]
    assert_equal 'Adar I', adar_i.month_name
  end

  def test_a_full_nineteen_year_cycle_has_seven_leap_years_and_legal_lengths
    [304, 305, 5784].each do |first_year|
      years = (first_year...(first_year + 19)).to_a
      leap_count = years.count { |year| @subject.leap_year?(year) }
      total_days = years.sum { |year| @subject.days_in_year(year) }
      kinds = years.map { |year| @subject.days_in_year(year) }.sort.uniq

      assert_equal 7, leap_count
      assert_equal 235, years.sum { |year| @subject.months_in_year(year) }
      assert_equal 12, @subject.months_in_year(5785)
      assert_equal 13, @subject.months_in_year(5784)
      assert total_days.between?(6939, 6942), "cycle #{first_year} was #{total_days} days"
      assert kinds.all? { |length| [353, 354, 355, 383, 384, 385].include?(length) }

      # Consecutive Rosh Hashanah dates are exactly days_in_year apart.
      years.each do |year|
        delta = @subject.to_gregorian(year + 1, :tishrei, 1) -
                @subject.to_gregorian(year, :tishrei, 1)
        assert_equal @subject.days_in_year(year), delta.to_i
      end
    end
  end

  def test_gregorian_year_occurrence_checks_both_overlapping_hebrew_years
    # Spring festivals: Gregorian year Y contains Nisan of Hebrew year Y+3761.
    assert_equal '2024-04-23', @subject.gregorian_year_occurrence(2024, :nisan, 15).to_s
    assert_equal '2025-04-13', @subject.gregorian_year_occurrence(2025, :nisan, 15).to_s
    # Winter festivals: 25 Kislev 5784 falls in December 2023.
    assert_equal '2023-12-08', @subject.gregorian_year_occurrence(2023, :kislev, 25).to_s

    # Unqualified :adar follows Purim: single Adar in common years, Adar II
    # in leap years.
    assert_equal '2023-03-07', @subject.gregorian_year_occurrence(2023, :adar, 14).to_s
    assert_equal '2024-03-24', @subject.gregorian_year_occurrence(2024, :adar, 14).to_s
    assert_equal '2025-03-14', @subject.gregorian_year_occurrence(2025, :adar, 14).to_s

    # Adar I exists only in a leap Hebrew year; 2025 contains no such month.
    assert_nil @subject.gregorian_year_occurrence(2025, :adar_i, 14)
    assert_equal '2024-02-23', @subject.gregorian_year_occurrence(2024, :adar_i, 14).to_s
  end

  def test_gregorian_year_occurrence_returns_nil_when_no_occurrence_exists
    # 30 Marcheshvan only exists in full years; when neither overlapping
    # Hebrew year is full, the Gregorian year has no occurrence.
    result = @subject.gregorian_year_occurrence(2024, :cheshvan, 30)
    assert(result.nil? || result.year == 2024)
  end

  def test_invalid_arguments_raise_readable_errors
    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :adar_ii, 1) }
    assert_match(/common Hebrew year 5785/, error.message)
    assert_match(/Adar II/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5784, :adar, 1) }
    assert_match(/ambiguous/, error.message)
    assert_match(/:adar_i/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :nisan, 31) }
    assert_match(/31/, error.message)
    assert_match(/Nisan 5785/, error.message)
    assert_match(/30 days/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :nissan, 1) }
    assert_match(/unknown Hebrew month :nissan/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5784, :cheshvan, 30) }
    assert_match(/30/, error.message)
    assert_match(/29 days/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, 14, 1) }
    assert_match(/unknown Hebrew month 14/, error.message)

    error = assert_raise(ArgumentError) { @subject.to_gregorian(5785, :nisan, 0) }
    assert_match(/day 0/, error.message)
  end
end
