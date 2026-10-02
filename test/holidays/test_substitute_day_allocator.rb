require File.expand_path(File.dirname(__FILE__)) + '/../test_helper'

require 'holidays/substitute_day_allocator'

class SubstituteDayAllocatorTests < Test::Unit::TestCase
  def setup
    @subject = Holidays::SubstituteDayAllocator.new
  end

  def holiday(name, year, month, day, regions = [:xx])
    {:name => name, :date => Date.civil(year, month, day), :regions => regions}
  end

  def year_end_holidays
    [
      holiday('Christmas Day', 2021, 12, 25),     # Saturday
      holiday('Boxing Day', 2021, 12, 26),        # Sunday
      holiday('Year-End Festival', 2021, 12, 27), # Monday
    ]
  end

  def test_weekday_holiday_keeps_its_original_date
    results = @subject.call([holiday('Year-End Festival', 2021, 12, 27)])

    assert_equal 1, results.length
    assert_equal Date.civil(2021, 12, 27), results[0][:date]
    assert_equal Date.civil(2021, 12, 27), results[0][:substitute_date]
    assert_equal [], results[0][:reasons]
  end

  def test_forward_strategy_moves_weekend_holiday_to_next_workday
    results = @subject.call([holiday('Christmas Day', 2021, 12, 25)], :strategy => :forward)

    assert_equal Date.civil(2021, 12, 25), results[0][:date]
    assert_equal Date.civil(2021, 12, 27), results[0][:substitute_date]
    assert_equal [:weekend], results[0][:reasons]
  end

  def test_backward_strategy_moves_weekend_holiday_to_previous_workday
    results = @subject.call([holiday('Christmas Day', 2021, 12, 25)], :strategy => :backward)

    assert_equal Date.civil(2021, 12, 24), results[0][:substitute_date]
    assert_equal [:weekend], results[0][:reasons]
  end

  def test_nearest_strategy_picks_closest_workday
    # Saturday: the previous Friday (1 day away) beats the next Monday (2 days).
    results = @subject.call([holiday('Christmas Day', 2021, 12, 25)], :strategy => :nearest)
    assert_equal Date.civil(2021, 12, 24), results[0][:substitute_date]

    # Sunday: the next Monday (1 day away) beats the previous Friday (2 days).
    results = @subject.call([holiday('Boxing Day', 2021, 12, 26)], :strategy => :nearest)
    assert_equal Date.civil(2021, 12, 27), results[0][:substitute_date]
  end

  def test_nearest_strategy_honours_tie_preference
    # With a Saturday/Sunday/Monday weekend, Sunday 2021-12-26 is equally far
    # from Tuesday 28th and Friday 24th; the tie preference decides.
    holidays = [holiday('Boxing Day', 2021, 12, 26)]
    weekends = {:xx => [6, 0, 1]}

    forward = @subject.call(holidays, :strategy => :nearest, :tie => :forward, :weekends => weekends)
    assert_equal Date.civil(2021, 12, 28), forward[0][:substitute_date]
    assert_equal [:weekend], forward[0][:reasons]

    backward = @subject.call(holidays, :strategy => :nearest, :tie => :backward, :weekends => weekends)
    assert_equal Date.civil(2021, 12, 24), backward[0][:substitute_date]
    assert_equal [:weekend], backward[0][:reasons]
  end

  def test_year_end_triple_collision_is_stable_across_input_orders
    expected = [
      {:name => 'Christmas Day', :date => Date.civil(2021, 12, 25),
       :substitute_date => Date.civil(2021, 12, 27), :reasons => [:weekend]},
      {:name => 'Boxing Day', :date => Date.civil(2021, 12, 26),
       :substitute_date => Date.civil(2021, 12, 28), :reasons => [:weekend, :occupied]},
      {:name => 'Year-End Festival', :date => Date.civil(2021, 12, 27),
       :substitute_date => Date.civil(2021, 12, 29), :reasons => [:occupied]},
    ]

    year_end_holidays.permutation.each do |ordering|
      results = @subject.call(ordering, :strategy => :forward)

      actual = results.map do |result|
        {:name => result[:name], :date => result[:date],
         :substitute_date => result[:substitute_date], :reasons => result[:reasons]}
      end
      assert_equal expected, actual, "allocation differed for input order #{ordering.map { |h| h[:name] }.inspect}"
    end
  end

  def test_region_specific_weekend_days
    holidays = [holiday('Founders Day', 2021, 12, 24, [:il])] # Friday

    results = @subject.call(holidays, :weekends => {:il => [5, 6]})
    assert_equal Date.civil(2021, 12, 26), results[0][:substitute_date]
    assert_equal [:weekend], results[0][:reasons]

    # Same date is a workday under the default Saturday/Sunday weekend.
    results = @subject.call(holidays)
    assert_equal Date.civil(2021, 12, 24), results[0][:substitute_date]
    assert_equal [], results[0][:reasons]
  end

  def test_same_name_holidays_from_different_regions_are_not_merged
    holidays = [
      holiday('Unity Day', 2021, 12, 25, [:xa]),
      holiday('Unity Day', 2021, 12, 25, [:xb]),
    ]

    results = @subject.call(holidays, :weekends => {:xa => [5, 6]})

    assert_equal 2, results.length
    by_region = results.each_with_object({}) { |r, h| h[r[:regions].first] = r }

    # Saturday is a weekend for both, but :xa rests Friday/Saturday so its
    # substitute lands on Sunday while :xb moves to Monday.
    assert_equal Date.civil(2021, 12, 26), by_region[:xa][:substitute_date]
    assert_equal Date.civil(2021, 12, 27), by_region[:xb][:substitute_date]
  end

  def test_holidays_from_different_regions_do_not_block_each_other
    holidays = [
      holiday('Alpha Day', 2021, 12, 25, [:xa]),
      holiday('Beta Day', 2021, 12, 25, [:xb]),
    ]

    results = @subject.call(holidays, :strategy => :forward)

    assert_equal [Date.civil(2021, 12, 27), Date.civil(2021, 12, 27)],
      results.map { |r| r[:substitute_date] }
    assert results.all? { |r| r[:reasons] == [:weekend] }
  end

  def test_cross_year_window_matches_full_year_allocation_sliced
    holidays = year_end_holidays + [
      holiday('New Year\'s Day', 2022, 1, 1),  # Saturday
      holiday('Second Day', 2022, 1, 2),        # Sunday
      holiday('Mid Year Day', 2021, 6, 15),     # Tuesday, outside the window
      holiday('Summer Day', 2022, 6, 1),        # Wednesday, outside the window
    ]
    from = Date.civil(2021, 12, 20)
    to = Date.civil(2022, 1, 10)

    windowed = @subject.call(holidays, :strategy => :forward, :from => from, :to => to)

    full = @subject.call(holidays, :strategy => :forward,
      :from => Date.civil(2021, 1, 1), :to => Date.civil(2022, 12, 31))
    sliced = full.select do |result|
      (from..to).cover?(result[:date]) ||
        (!result[:substitute_date].nil? && (from..to).cover?(result[:substitute_date]))
    end

    assert_equal 5, windowed.length
    assert_equal sliced, windowed
    assert_equal [
      Date.civil(2021, 12, 27), Date.civil(2021, 12, 28), Date.civil(2021, 12, 29),
      Date.civil(2022, 1, 3), Date.civil(2022, 1, 4),
    ], windowed.map { |r| r[:substitute_date] }
  end

  def test_unassigned_when_no_position_inside_search_range
    # Backwards from Saturday 2022-01-01 there is no workday left inside 2022.
    results = @subject.call([holiday('New Year\'s Day', 2022, 1, 1)],
      :strategy => :backward, :from => Date.civil(2022, 1, 1), :to => Date.civil(2022, 1, 15))

    assert_equal 1, results.length
    assert_equal Date.civil(2022, 1, 1), results[0][:date]
    assert_nil results[0][:substitute_date]
    assert_equal [:weekend, :no_available_date], results[0][:reasons]
  end

  def test_unassigned_when_all_remaining_workdays_are_occupied
    holidays = [
      holiday('First', 2022, 1, 3), # Monday, stays put
      holiday('Second', 2022, 1, 3),
    ]

    results = @subject.call(holidays, :strategy => :backward,
      :from => Date.civil(2022, 1, 3), :to => Date.civil(2022, 1, 31))

    assert_equal Date.civil(2022, 1, 3), results[0][:substitute_date]
    assert_nil results[1][:substitute_date]
    assert_equal [:occupied, :no_available_date], results[1][:reasons]
  end

  def test_results_keep_original_date_name_and_regions
    results = @subject.call([holiday('Christmas Day', 2021, 12, 25, [:us, :us_ca])])

    assert_equal 'Christmas Day', results[0][:name]
    assert_equal [:us, :us_ca], results[0][:regions]
    assert_equal Date.civil(2021, 12, 25), results[0][:date]
  end

  def test_module_level_entry_point
    results = Holidays.allocate_substitutes(year_end_holidays, :strategy => :forward)

    assert_equal Date.civil(2021, 12, 27), results[0][:substitute_date]
    assert_equal Date.civil(2021, 12, 29), results[2][:substitute_date]
  end

  def test_accepts_output_of_between
    holidays = Holidays.between(Date.civil(2021, 12, 20), Date.civil(2022, 1, 5), :us)

    results = Holidays.allocate_substitutes(holidays, :strategy => :forward)
    by_name = results.each_with_object({}) { |r, h| h[r[:name]] = r }

    assert_equal Date.civil(2021, 12, 25), by_name['Christmas Day'][:date]
    assert_equal Date.civil(2021, 12, 27), by_name['Christmas Day'][:substitute_date]
    assert_equal Date.civil(2022, 1, 1), by_name['New Year\'s Day'][:date]
    assert_equal Date.civil(2022, 1, 3), by_name['New Year\'s Day'][:substitute_date]
  end

  def test_default_strategy_is_forward
    results = @subject.call([holiday('Christmas Day', 2021, 12, 25)])

    assert_equal Date.civil(2021, 12, 27), results[0][:substitute_date]
  end

  def test_empty_input_returns_empty_array
    assert_equal [], @subject.call([])
  end

  def test_unknown_strategy_raises
    assert_raise(ArgumentError) { @subject.call(year_end_holidays, :strategy => :sideways) }
  end

  def test_unknown_tie_preference_raises
    assert_raise(ArgumentError) { @subject.call(year_end_holidays, :tie => :sideways) }
  end

  def test_missing_name_or_date_raises
    assert_raise(ArgumentError) { @subject.call([{:date => Date.civil(2021, 12, 25)}]) }
    assert_raise(ArgumentError) { @subject.call([{:name => 'Christmas Day'}]) }
  end

  def test_non_array_input_raises
    assert_raise(ArgumentError) { @subject.call('not an array') }
  end

  def test_from_after_to_raises
    assert_raise(ArgumentError) do
      @subject.call(year_end_holidays, :from => Date.civil(2022, 1, 1), :to => Date.civil(2021, 1, 1))
    end
  end
end
