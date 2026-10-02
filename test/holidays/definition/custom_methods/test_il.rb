require File.expand_path(File.dirname(__FILE__)) + '/../../../test_helper'

require 'holidays/definition/custom_methods/il'

# Dates fixed in the arithmetic Hebrew calendar. The old il definition
# carried every occurrence 2022-2026 as a hand-copied civil-date table; these
# anchors prove the calculator reproduces those years and continues resolving
# past them, including the leap-year Adar II naming.
class ILCustomMethodsTests < Test::Unit::TestCase
  JEWISH_NEW_YEAR = {
    2022 => '2022-09-26', 2023 => '2023-09-16', 2024 => '2024-10-03',
    2025 => '2025-09-23', 2026 => '2026-09-12', 2030 => '2030-09-28',
  }.freeze

  DAY_OF_ATONEMENT = {
    2022 => '2022-10-05', 2023 => '2023-09-25', 2024 => '2024-10-12',
    2025 => '2025-10-02', 2026 => '2026-09-21', 2030 => '2030-10-07',
  }.freeze

  FEAST_OF_TABERNACLES = {
    2022 => '2022-10-10', 2023 => '2023-09-30', 2024 => '2024-10-17',
    2025 => '2025-10-07', 2026 => '2026-09-26', 2030 => '2030-10-12',
  }.freeze

  REJOICING_OF_THE_TORAH = {
    2022 => '2022-10-18', 2023 => '2023-10-08', 2024 => '2024-10-25',
    2025 => '2025-10-15', 2026 => '2026-10-04', 2030 => '2030-10-20',
  }.freeze

  EXODUS = {
    2022 => '2022-03-16', 2023 => '2023-03-06', 2024 => '2024-03-23',
    2025 => '2025-03-13', 2026 => '2026-03-02', 2030 => '2030-03-18',
  }.freeze

  EXODUS_DAY_7 = {
    2022 => '2022-03-22', 2023 => '2023-03-12', 2024 => '2024-03-29',
    2025 => '2025-03-19', 2026 => '2026-03-08',
  }.freeze

  def test_each_holiday_matches_reference_dates
    JEWISH_NEW_YEAR.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.jewish_new_year(year).to_s
      assert_equal((Date.parse(expected) + 1).to_s, Holidays::Definition::CustomMethods::IL.second_new_year_day(year).to_s)
    end

    DAY_OF_ATONEMENT.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.day_of_atonement(year).to_s
    end

    FEAST_OF_TABERNACLES.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.feast_of_tabernacles(year).to_s
    end

    REJOICING_OF_THE_TORAH.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.rejoicing_of_the_torah(year).to_s
    end

    EXODUS.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.exodus_from_egypt(year).to_s
    end

    EXODUS_DAY_7.each do |year, expected|
      assert_equal expected, Holidays::Definition::CustomMethods::IL.exodus_from_egypt_day_7(year).to_s
    end
  end

end
