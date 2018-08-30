module ExceptionNotifier
  module BacktraceCleaner

    def clean_backtrace(exception, backtrace_cleaner=nil)
      if !backtrace_cleaner.nil?
        backtrace_cleaner.clean(exception.backtrace, :silent)
      elsif defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
        Rails.backtrace_cleaner.clean(exception.backtrace, :silent)
      else
        exception.backtrace
      end
    end

  end
end
