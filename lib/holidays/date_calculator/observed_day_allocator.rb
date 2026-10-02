module Holidays
  module DateCalculator
    class ObservedDayAllocator
      DEFAULT_WEEKEND_DAYS = [0, 6].freeze

      STRATEGIES = {
        :forward => :forward,
        :after => :forward,
        :next => :forward,
        :backward => :backward,
        :before => :backward,
        :previous => :backward,
        :nearest_weekday => :nearest,
        :nearest => :nearest,
        :nearest_working_day => :nearest,
        :closest_weekday => :nearest,
        :closest_working_day => :nearest,
      }.freeze

      TIE_PREFERENCES = {
        :forward => :forward,
        :after => :forward,
        :later => :forward,
        :backward => :backward,
        :before => :backward,
        :earlier => :backward,
        :future => :forward,
        :past => :backward,
      }.freeze

      def self.call(holidays, **options)
        weekends = options[:weekends] ||
          options[:weekend_days_by_region] ||
          options[:region_weekends] || {}
        default_weekend_days = if options.key?(:default_weekend_days)
          options[:default_weekend_days]
        else
          options.fetch(:default_weekend, DEFAULT_WEEKEND_DAYS)
        end

        call_options = options.except(
          :weekends,
          :weekend_days_by_region,
          :region_weekends,
          :default_weekend_days,
          :default_weekend,
        )

        new(
          weekends: weekends,
          default_weekend_days: default_weekend_days,
        ).call(holidays, **call_options)
      end

      def initialize(weekends: {}, default_weekend_days: DEFAULT_WEEKEND_DAYS)
        @weekends = normalize_weekends(weekends)
        @default_weekend_days = normalize_weekend_days(default_weekend_days, :default)
      end

      def call(holidays, strategy: :nearest_weekday, tie_preference: :forward,
               same_distance_preference: nil, equidistant_preference: nil,
               search_range: nil, within: nil, range: nil, output_range: nil,
               **unexpected_options)
        unless unexpected_options.empty?
          raise ArgumentError, "unknown options: #{unexpected_options.keys.join(', ')}"
        end

        selected_tie = tie_preference || same_distance_preference || equidistant_preference
        direction, tie = normalize_strategy(strategy, selected_tie)
        search_range = normalize_range(search_range, :search_range)
        search_range ||= normalize_range(range, :range)
        within = normalize_range(within, :within)
        within ||= normalize_range(output_range, :output_range)

        normalized_holidays = holidays.each_with_index.map { |holiday, index| normalize_holiday(holiday, index) }
        return [] if normalized_holidays.empty?

        years = normalized_holidays.map { |holiday| holiday[:original_date].year }
        context_range = Date.civil(years.min - 1, 1, 1)..Date.civil(years.max + 1, 12, 31)
        effective_search_range = search_range || context_range

        occupied = initial_occupancy(normalized_holidays)
        results = normalized_holidays.sort_by(&method(:holiday_order)).map do |holiday|
          allocate_holiday(holiday, direction, tie, effective_search_range, occupied)
        end

        slice_results(results.sort_by(&method(:holiday_order)), within)
      end

      private

      def normalize_weekends(weekends)
        weekends.to_h.each_with_object({}) do |(region, days), normalized|
          normalized[region.to_sym] = normalize_weekend_days(days, region)
        end
      end

      def normalize_weekend_days(days, region)
        normalized = Array(days).map do |day|
          day = DAY_SYMBOLS.index(day.to_s.downcase.to_sym) if day.is_a?(Symbol) || day.is_a?(String)
          raise ArgumentError, "invalid weekend day for #{region}: #{day.inspect}" unless day.is_a?(Integer) && day.between?(0, 6)
          day
        end.uniq.sort

        raise ArgumentError, "weekend days for #{region} cannot be empty" if normalized.empty?
        raise ArgumentError, "weekend days for #{region} cannot include every weekday" if normalized.length == 7
        normalized
      end

      def normalize_range(range, name)
        return nil if range.nil?
        raise ArgumentError, "#{name} must be a Date range" unless range.is_a?(Range) && range.begin.is_a?(Date) && range.end.is_a?(Date)
        range
      end

      def normalize_holiday(holiday, index)
        unless holiday.is_a?(Hash)
          raise ArgumentError, "holiday at index #{index} must be a hash"
        end

        original_date = holiday[:original_date] || holiday[:date]
        unless original_date.is_a?(Date)
          raise ArgumentError, "holiday at index #{index} must have a Date"
        end

        regions = Array(holiday[:regions])
        regions = Array(holiday[:region]) if regions.empty?
        regions = regions.map(&:to_sym)
        regions = [:unknown] if regions.empty?

        normalized = holiday.dup
        normalized[:date] = original_date
        normalized[:original_date] = original_date
        normalized[:regions] = regions.dup
        normalized[:region] = regions.first unless normalized.key?(:region)
        priority = normalized.fetch(:priority, Float::INFINITY)
        unless priority == Float::INFINITY || priority.is_a?(Numeric)
          raise ArgumentError, "holiday at index #{index} has an invalid priority"
        end
        normalized[:priority] = priority
        normalized[:_input_index] = index
        normalized
      end

      def normalize_strategy(strategy, default_tie)
        if strategy.is_a?(Hash)
          direction = normalized_strategy_value(
            strategy[:direction] ||
              strategy[:strategy] ||
              strategy[:mode] ||
              strategy["direction"] ||
              strategy["strategy"] ||
              strategy["mode"],
          )
          tie = normalized_tie_value(
            strategy[:tie] ||
              strategy[:tie_preference] ||
              strategy[:same_distance_preference] ||
              strategy[:equidistant_preference] ||
              strategy["tie"] ||
              strategy["tie_preference"] ||
              strategy["same_distance_preference"] ||
              strategy["equidistant_preference"] ||
              default_tie,
          )
        else
          direction = normalized_strategy_value(strategy)
          tie = normalized_tie_value(default_tie)
        end
        tie = :forward if tie.nil?

        normalized_direction = STRATEGIES[direction] || STRATEGIES[normalized_strategy_value(direction)]
        normalized_tie = TIE_PREFERENCES[tie] || TIE_PREFERENCES[normalized_tie_value(tie)]

        raise ArgumentError, "unknown allocation strategy: #{strategy.inspect}" unless normalized_direction
        raise ArgumentError, "unknown tie preference: #{tie.inspect}" unless normalized_tie

        [normalized_direction, normalized_tie]
      end

      def normalized_strategy_value(value)
        value = value.to_sym if value.respond_to?(:to_sym) && !value.is_a?(Symbol)
        value
      end

      def normalized_tie_value(value)
        value = value.to_sym if value.respond_to?(:to_sym) && !value.is_a?(Symbol)
        value
      end

      def initial_occupancy(holidays)
        holidays.each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |holiday, occupied|
          holiday[:regions].each do |region|
            occupied[region][holiday[:original_date]] = holiday_identity(holiday)
          end
        end
      end

      def allocate_holiday(holiday, direction, tie, search_range, occupied)
        region = holiday[:regions].first
        original_date = holiday[:original_date]

        result = holiday.reject { |key, _| key == :_input_index }
        unless weekend?(region, original_date)
          result[:date] = original_date
          result[:allocation_status] = :not_required
          result[:observed] = false
          result[:observed_reason] = nil
          return result
        end

        observed_date = find_observed_date(original_date, region, direction, tie, search_range, occupied)

        if observed_date
          mark_occupied(holiday, observed_date, occupied)
          result[:date] = observed_date
          result[:observed_date] = observed_date
          result[:makeup_date] = observed_date
          result[:allocation_status] = :allocated
          result[:observed] = true
          result[:observed_reason] = :original_date_on_weekend
          result[:makeup_reason] = result[:observed_reason]
          result[:reason] = result[:observed_reason]
        else
          result[:date] = nil
          result[:observed_date] = nil
          result[:makeup_date] = nil
          result[:allocation_status] = :unallocated
          result[:observed] = false
          result[:observed_reason] = :no_available_weekday_in_search_range
          result[:makeup_reason] = result[:observed_reason]
          result[:reason] = result[:observed_reason]
        end

        result
      end

      def find_observed_date(original_date, region, direction, tie, search_range, occupied)
        candidates(original_date, direction, tie, search_range).find do |candidate|
          search_range.cover?(candidate) &&
            !weekend?(region, candidate) &&
            !occupied.fetch(region, {}).key?(candidate)
        end
      end

      def candidates(original_date, direction, tie, search_range)
        forward_limit = search_range.end - original_date
        backward_limit = original_date - search_range.begin

        case direction
        when :forward
          Enumerator.new do |yielder|
            1.upto(forward_limit) { |offset| yielder << original_date + offset }
          end
        when :backward
          Enumerator.new do |yielder|
            1.upto(backward_limit) { |offset| yielder << original_date - offset }
          end
        else
          maximum_offset = [forward_limit, backward_limit].max
          Enumerator.new do |yielder|
            1.upto(maximum_offset) do |offset|
              earlier = original_date - offset
              later = original_date + offset
              yielder << (tie == :forward ? later : earlier)
              yielder << (tie == :forward ? earlier : later)
            end
          end
        end
      end

      def mark_occupied(holiday, date, occupied)
        holiday[:regions].each do |region|
          occupied[region][date] = holiday_identity(holiday)
        end
      end

      def weekend?(region, date)
        weekend_days = @weekends.fetch(region, @default_weekend_days)
        weekend_days.include?(date.wday)
      end

      def holiday_order(holiday)
        [
          priority_order(holiday[:priority]),
          holiday[:original_date],
          holiday[:name].to_s,
          holiday[:regions],
          holiday[:_input_index],
        ]
      end

      def priority_order(priority)
        return priority if priority.is_a?(Numeric)
        Float::INFINITY
      end

      def holiday_identity(holiday)
        [holiday[:name], holiday[:original_date], holiday[:regions]]
      end

      def slice_results(results, within)
        return results unless within
        results.select { |holiday| within.cover?(holiday[:date] || holiday[:original_date]) }
      end
    end
  end
end
