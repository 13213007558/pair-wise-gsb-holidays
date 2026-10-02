require File.expand_path(File.dirname(__FILE__)) + '/../../test_helper'

require 'holidays/date_calculator/observed_day_allocator'

class ObservedDayAllocatorTests < Test::Unit::TestCase
  def setup
    @weekends = {
      :standard => [0, 6],
      :long_weekend => [0, 5, 6],
    }
    @subject = Holidays::DateCalculator::ObservedDayAllocator.new(weekends: @weekends)
  end

  def test_year_end_three_holiday_collision_is_stable_across_input_orders
    holidays = [
      {
        date: Date.civil(2022, 1, 1),
        name: "New Year's Day",
        regions: [:standard],
        priority: 3,
      },
      {
        date: Date.civil(2021, 12, 26),
        name: "Boxing Day",
        regions: [:standard],
        priority: 2,
      },
      {
        date: Date.civil(2021, 12, 25),
        name: "Christmas Day",
        regions: [:standard],
        priority: 1,
      },
    ]

    expected = {
      "Christmas Day" => Date.civil(2021, 12, 24),
      "Boxing Day" => Date.civil(2021, 12, 27),
      "New Year's Day" => Date.civil(2021, 12, 31),
    }

    [holidays, holidays.reverse, holidays.shuffle(random: Random.new(7))].each do |ordered_holidays|
      results = @subject.call(
        ordered_holidays,
        strategy: :nearest_weekday,
        tie_preference: :forward,
      )

      actual = results.each_with_object({}) do |result, allocated|
        assert_equal(:allocated, result[:allocation_status])
        assert_equal(:original_date_on_weekend, result[:observed_reason])
        assert_equal(result[:observed_date], result[:date])
        assert_equal(result[:original_date], result[:date] - (result[:date] - result[:original_date]))
        allocated[result[:name]] = result[:date]
      end

      assert_equal(expected, actual)
    end
  end

  def test_forward_strategy_skips_dates_already_occupied_by_higher_priority
    holidays = [
      {
        date: Date.civil(2021, 12, 26),
        name: "Second Holiday",
        regions: [:standard],
        priority: 2,
      },
      {
        date: Date.civil(2021, 12, 25),
        name: "First Holiday",
        regions: [:standard],
        priority: 1,
      },
    ]

    results = @subject.call(holidays, strategy: :forward)
    dates = results.map { |result| [result[:name], result[:date]] }.to_h

    assert_equal(Date.civil(2021, 12, 27), dates["First Holiday"])
    assert_equal(Date.civil(2021, 12, 28), dates["Second Holiday"])
  end

  def test_backward_strategy_skips_occupied_dates
    holidays = [
      {
        date: Date.civil(2021, 12, 26),
        name: "Second Holiday",
        regions: [:standard],
        priority: 2,
      },
      {
        date: Date.civil(2021, 12, 25),
        name: "First Holiday",
        regions: [:standard],
        priority: 1,
      },
    ]

    results = @subject.call(holidays, strategy: :backward)
    dates = results.map { |result| [result[:name], result[:date]] }.to_h

    assert_equal(Date.civil(2021, 12, 24), dates["First Holiday"])
    assert_equal(Date.civil(2021, 12, 23), dates["Second Holiday"])
  end

  def test_nearest_strategy_honors_same_distance_preference
    holidays = [
      {
        date: Date.civil(2021, 12, 25),
        name: "Middle Weekend Day",
        regions: [:long_weekend],
      }
    ]

    forward = @subject.call(
      holidays,
      strategy: {direction: :nearest, tie: :forward},
    )
    backward = @subject.call(
      holidays,
      strategy: {direction: :nearest, tie: :backward},
    )

    assert_equal(Date.civil(2021, 12, 27), forward.first[:date])
    assert_equal(Date.civil(2021, 12, 23), backward.first[:date])
  end

  def test_search_range_without_available_weekday_returns_unallocated_item
    holidays = [
      {
        date: Date.civil(2021, 12, 25),
        name: "No Room Holiday",
        regions: [:standard],
      }
    ]

    result = @subject.call(
      holidays,
      strategy: :forward,
      search_range: Date.civil(2021, 12, 25)..Date.civil(2021, 12, 26),
    ).first

    assert_nil(result[:date])
    assert_equal(Date.civil(2021, 12, 25), result[:original_date])
    assert_equal(:unallocated, result[:allocation_status])
    assert_equal(:no_available_weekday_in_search_range, result[:observed_reason])
    assert_equal(result[:observed_reason], result[:reason])
  end

  def test_range_alias_limits_the_search_range
    holidays = [
      {
        date: Date.civil(2021, 12, 26),
        name: "Limited Range Holiday",
        regions: [:standard],
      }
    ]

    result = @subject.call(
      holidays,
      strategy: "forward",
      range: Date.civil(2021, 12, 26)..Date.civil(2021, 12, 26),
    ).first

    assert_equal(:unallocated, result[:allocation_status])
  end

  def test_region_weekends_accept_day_name_symbols
    holidays = [
      {
        date: Date.civil(2021, 12, 24),
        name: "Friday Weekend Holiday",
        regions: [:named_weekend],
      }
    ]

    result = Holidays.allocate_observed_days(
      holidays,
      weekends: {named_weekend: [:friday, :saturday]},
      strategy: :forward,
    ).first

    assert_equal(Date.civil(2021, 12, 26), result[:date])
  end

  def test_cross_year_slice_matches_full_relevant_years_then_slice
    holidays = [
      {
        date: Date.civil(2022, 1, 1),
        name: "New Year's Day",
        regions: [:standard],
        priority: 3,
      },
      {
        date: Date.civil(2021, 12, 26),
        name: "Boxing Day",
        regions: [:standard],
        priority: 2,
      },
      {
        date: Date.civil(2021, 12, 25),
        name: "Christmas Day",
        regions: [:standard],
        priority: 1,
      },
    ]
    slice = Date.civil(2021, 12, 30)..Date.civil(2022, 1, 2)

    full_results = @subject.call(
      holidays,
      strategy: :nearest_weekday,
      tie_preference: :forward,
    )
    sliced_from_full = full_results.select { |result| slice.cover?(result[:date]) }
    directly_sliced = @subject.call(
      holidays,
      strategy: :nearest_weekday,
      tie_preference: :forward,
      within: slice,
    )

    assert_equal(sliced_from_full, directly_sliced)
    assert_equal(["New Year's Day"], directly_sliced.map { |result| result[:name] })
    assert_equal(Date.civil(2021, 12, 31), directly_sliced.first[:date])
  end

  def test_same_named_holidays_in_different_regions_do_not_share_occupancy
    holidays = [
      {
        date: Date.civil(2021, 12, 25),
        name: "Shared Holiday Name",
        regions: [:standard],
        region: :standard,
      },
      {
        date: Date.civil(2021, 12, 25),
        name: "Shared Holiday Name",
        regions: [:other],
        region: :other,
      },
    ]

    results = Holidays.allocate_makeup_days(holidays, strategy: :forward)

    assert_equal(2, results.length)
    assert(results.all? { |result| result[:date] == Date.civil(2021, 12, 27) })
    regions = results.map { |result| result[:region].to_s }.sort
    assert_equal(["other", "standard"], regions)
  end

  def test_weekday_holiday_keeps_original_date_without_a_makeup_reason
    holidays = [
      {
        date: Date.civil(2021, 12, 24),
        name: "Weekday Holiday",
        regions: [:standard],
      }
    ]

    result = @subject.call(holidays).first

    assert_equal(Date.civil(2021, 12, 24), result[:date])
    assert_equal(:not_required, result[:allocation_status])
    assert_nil(result[:observed_reason])
  end
end
