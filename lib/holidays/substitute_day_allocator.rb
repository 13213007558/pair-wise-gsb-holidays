module Holidays
  # Allocates substitute (compensatory) rest days for a group of holidays.
  #
  # When several holidays land on a weekend, shifting each one independently
  # can move them onto the same workday. This allocator instead processes the
  # whole group in a deterministic priority order (original date, then name,
  # then regions) and lets each holiday claim the first date produced by the
  # chosen strategy that:
  #
  # * is a workday for the holiday's region (weekend days are region-specific),
  # * is not already claimed by another holiday sharing one of its regions,
  # * lies inside the search range.
  #
  # Because the priority order does not depend on input order, the resulting
  # allocation (and the recorded reasons) is stable no matter how the input
  # holidays were ordered.
  #
  # Each result keeps the holiday's original date, the substitute date (or nil
  # when no position was available inside the search range) and the reasons
  # that led to the substitute:
  #
  # * :weekend -- the original date falls on a weekend for the holiday's region
  # * :occupied -- one or more candidate workdays were already claimed
  # * :no_available_date -- no position was available inside the search range
  #
  # Holidays are never merged: two holidays with the same name but different
  # regions remain separate entries and do not compete for the same dates.
  #
  # The search range spans the full calendar years covering both the query
  # window (:from/:to) and the original dates of all given holidays. Querying
  # a small window that crosses a year boundary therefore yields exactly the
  # same allocation as querying the full relevant years and slicing the
  # results down to the window.
  class SubstituteDayAllocator
    DEFAULT_WEEKEND = [0, 6].freeze

    STRATEGIES = [:forward, :backward, :nearest].freeze
    TIE_PREFERENCES = [:forward, :backward].freeze

    REASON_WEEKEND = :weekend
    REASON_OCCUPIED = :occupied
    REASON_NO_AVAILABLE_DATE = :no_available_date

    # holidays: array of hashes with :name, :date and :regions keys, such as
    # the hashes returned by Holidays.between.
    #
    # options:
    # * :strategy - :forward (default), :backward or :nearest
    # * :tie - for :nearest, which direction wins when both are equally close:
    #   :forward (default) or :backward
    # * :weekends - hash of region => array of weekend wdays (0 = Sunday),
    #   with an optional :default entry; defaults to Saturday/Sunday
    # * :from, :to - query window; only holidays whose original or substitute
    #   date falls inside it are returned. Defaults to the span of the given
    #   holiday dates.
    def call(holidays, options = {})
      strategy = options.fetch(:strategy, :forward)
      tie_preference = options.fetch(:tie, :forward)
      validate_options!(strategy, tie_preference)

      entries = normalize(holidays)
      return [] if entries.empty?

      from, to = query_window(entries, options)
      search_from, search_to = search_range(entries, from, to)
      weekends = normalize_weekends(options[:weekends])

      claimed = []

      results = prioritized(entries).map do |entry|
        weekend_days = weekend_days_for(weekends, entry[:regions])
        reasons = []
        reasons << REASON_WEEKEND if weekend_days.include?(entry[:date].wday)

        substitute = nil
        each_candidate(entry[:date], strategy, tie_preference, search_from, search_to) do |candidate|
          next if weekend_days.include?(candidate.wday)

          if claimed?(claimed, candidate, entry[:regions])
            reasons << REASON_OCCUPIED unless reasons.include?(REASON_OCCUPIED)
            next
          end

          substitute = candidate
          break
        end

        if substitute.nil?
          reasons << REASON_NO_AVAILABLE_DATE
        else
          claimed << [substitute, entry[:regions]]
        end

        {
          :name => entry[:name],
          :regions => entry[:regions],
          :date => entry[:date],
          :substitute_date => substitute,
          :reasons => reasons,
        }
      end

      results.select { |result| in_window?(result, from, to) }
    end

    private

    # Deterministic priority order: earlier original dates claim dates first,
    # with name and regions as tie-breakers so the allocation never depends on
    # the order the holidays were supplied in.
    def prioritized(entries)
      entries.sort_by do |entry|
        [entry[:date], entry[:name].to_s, entry[:regions].map(&:to_s).sort]
      end
    end

    def validate_options!(strategy, tie_preference)
      unless STRATEGIES.include?(strategy)
        raise ArgumentError, "unknown strategy #{strategy.inspect}; expected one of #{STRATEGIES.inspect}"
      end

      unless TIE_PREFERENCES.include?(tie_preference)
        raise ArgumentError, "unknown tie preference #{tie_preference.inspect}; expected one of #{TIE_PREFERENCES.inspect}"
      end
    end

    def normalize(holidays)
      raise ArgumentError, 'holidays must be an Array' unless holidays.is_a?(Array)

      holidays.map do |holiday|
        name = holiday[:name]
        date = holiday[:date]
        regions = holiday[:regions]

        raise ArgumentError, 'each holiday must include a :name' if name.nil?
        raise ArgumentError, 'each holiday must include a :date' if date.nil?

        date = date.to_date if date.respond_to?(:to_date)
        unless date.respond_to?(:wday)
          raise ArgumentError, 'each holiday :date must be a Date (or respond to #to_date)'
        end

        {
          :name => name,
          :date => date,
          :regions => Array(regions).map(&:to_sym),
        }
      end
    end

    def query_window(entries, options)
      from = options[:from] || entries.map { |entry| entry[:date] }.min
      to = options[:to] || entries.map { |entry| entry[:date] }.max

      from = from.to_date if from.respond_to?(:to_date)
      to = to.to_date if to.respond_to?(:to_date)

      raise ArgumentError, ':from must not be after :to' if to < from

      [from, to]
    end

    # The search range covers the full calendar years of both the query window
    # and every holiday's original date, so that a partial (e.g. cross-year)
    # query allocates exactly like the full-year query it was sliced from.
    def search_range(entries, from, to)
      years = entries.map { |entry| entry[:date].year }
      years << from.year
      years << to.year

      [Date.civil(years.min, 1, 1), Date.civil(years.max, 12, 31)]
    end

    def normalize_weekends(weekends)
      (weekends || {}).each_with_object({}) do |(region, days), normalized|
        normalized[region.to_sym] = Array(days).map(&:to_i)
      end
    end

    def weekend_days_for(weekends, regions)
      regions.each do |region|
        return weekends[region] if weekends.key?(region)
      end

      weekends[:default] || DEFAULT_WEEKEND
    end

    def claimed?(claimed, date, regions)
      claimed.any? do |claimed_date, claimed_regions|
        claimed_date == date && (claimed_regions & regions).any?
      end
    end

    def each_candidate(date, strategy, tie_preference, search_from, search_to)
      case strategy
      when :forward
        candidate = date
        while candidate <= search_to
          yield candidate
          candidate += 1
        end
      when :backward
        candidate = date
        while candidate >= search_from
          yield candidate
          candidate -= 1
        end
      when :nearest
        distance = 0
        loop do
          forward = date + distance
          backward = date - distance
          break if forward > search_to && backward < search_from

          candidates = if distance.zero?
            [date]
          elsif tie_preference == :backward
            [backward, forward]
          else
            [forward, backward]
          end

          candidates.each do |candidate|
            next if candidate < search_from || candidate > search_to
            yield candidate
          end

          distance += 1
        end
      end
    end

    def in_window?(result, from, to)
      (from..to).cover?(result[:date]) ||
        (!result[:substitute_date].nil? && (from..to).cover?(result[:substitute_date]))
    end
  end
end
