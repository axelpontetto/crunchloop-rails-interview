module Sync
  # Accumulates the per-record outcome of a sync run so the rake task can print
  # it and tests can assert on it. Never raises — a failed action is recorded,
  # not propagated, so partial failures don't abort the whole run.
  class Result
    Outcome = Struct.new(:status, :kind, :label, :error, keyword_init: true)

    attr_reader :outcomes

    def initialize
      @outcomes = []
    end

    def record(status, action, error: nil)
      @outcomes << Outcome.new(status: status, kind: action.kind, label: action.label, error: error&.message)
    end

    def counts
      @outcomes.group_by(&:status).transform_values(&:size)
    end

    def failures
      @outcomes.select { |o| o.status == :failed }
    end

    def failed?
      failures.any?
    end

    def to_s
      lines = ["Sync result: #{counts.map { |s, n| "#{s}=#{n}" }.join(', ')}"]
      failures.each { |o| lines << "  FAILED #{o.kind} #{o.label}: #{o.error}" }
      lines.join("\n")
    end
  end
end
