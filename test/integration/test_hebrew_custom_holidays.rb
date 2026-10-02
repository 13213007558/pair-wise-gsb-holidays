require File.expand_path(File.dirname(__FILE__)) + '/../test_helper'

class HebrewCustomHolidaysIntegrationTests < Test::Unit::TestCase
  DEFINITION_FILE = File.expand_path(
    File.dirname(__FILE__) + '/data/test_hebrew_custom_holiday_defs.yaml'
  )

  def setup
    Holidays.load_custom(DEFINITION_FILE)
  end

  def test_fall_and_spring_dates_resolve_without_using_gregorian_year_as_hebrew_year
    assert_equal 'Fall Hebrew Test', Holidays.on(Date.new(2024, 10, 13), :custom_hebrew).first[:name]
    assert_equal 'Common Adar Hebrew Test', Holidays.on(Date.new(2025, 3, 13), :custom_hebrew).first[:name]
    assert_equal 'Leap Adar Test', Holidays.on(Date.new(2024, 2, 23), :custom_hebrew).first[:name]
    assert_empty Holidays.on(Date.new(2025, 2, 24), :custom_hebrew)
  end

  def test_range_that_crosses_two_hebrew_years_returns_holidays_from_both
    holidays = Holidays.between(Date.new(2024, 10, 1), Date.new(2025, 4, 15), :custom_hebrew)

    assert_equal [Date.new(2024, 10, 13), Date.new(2025, 3, 13)], holidays.map { |holiday| holiday[:date] }
  end

  def test_invalid_hebrew_month_is_rejected_when_definitions_load
    File.stubs(:read)
    YAML.stubs(:load_file).with(anything).returns(
      'months' => {
        0 => [
          {
            'name' => 'Bad Month',
            'regions' => ['custom_hebrew_bad'],
            'hebrew_month' => 'veadar',
            'hebrew_day' => 1,
          },
        ],
      },
    )

    error = assert_raise(ArgumentError) { Holidays.load_custom('bad.yaml') }
    assert_match(/unknown Hebrew month/, error.message)
  ensure
    YAML.unstub(:load_file)
  end

  def test_invalid_hebrew_day_is_rejected_when_definitions_load
    YAML.stubs(:load_file).with(anything).returns(
      'months' => {
        0 => [
          {
            'name' => 'Bad Day',
            'regions' => ['custom_hebrew_bad'],
            'hebrew_month' => 'adar',
            'hebrew_day' => 30,
          },
        ],
      },
    )

    error = assert_raise(ArgumentError) { Holidays.load_custom('bad.yaml') }
    assert_equal 'day 30 does not exist in adar', error.message
  ensure
    YAML.unstub(:load_file)
  end
end
