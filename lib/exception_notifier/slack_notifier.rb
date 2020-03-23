module ExceptionNotifier
  class SlackNotifier < BaseNotifier
    include ExceptionNotifier::BacktraceCleaner

    attr_accessor :notifier

    def initialize(options)
      super
      @ignore_data_if = options[:ignore_data_if]
      @backtrace_lines = options.fetch(:backtrace_lines, 10)
      @additional_fields = options[:additional_fields]
      @message_opts = options.fetch(:additional_parameters, {})
      @color = @message_opts.delete(:color) { 'danger' }
      @options = options
      @notifiers = {}
    end

    def notifier_for(channel)
      channel = channel || @options[:channel]
      options = @options.merge(channel: channel)
      @notifiers[channel] ||= Slack::Notifier.new @options[:webhook_url], options
    rescue
      nil
    end

    def call(exception, options={})
      current_channel = options[:channel]
      notifier = notifier_for(current_channel)
      errors_count = options[:accumulated_errors_count].to_i

      measure_word = if errors_count > 1
                       errors_count
                     else
                       exception_class.to_s =~ /^[aeiou]/i ? 'An' : 'A'
                     end

      exception_name = "*#{measure_word}* `#{exception_class}`"
      env = options[:env]

      if env.nil?
        data = options[:data] || {}
        text = "#{exception_name} *occured in background*\n"
      else
        data = (env['exception_notifier.exception_data'] || {}).merge(options[:data] || {})

        kontroller = env['action_controller.instance']
        request = "#{env['REQUEST_METHOD']} <#{env['REQUEST_URI']}>"
        text = "#{exception_name} *occurred while* `#{request}`"
        text += " *was processed by* `#{kontroller.controller_name}##{kontroller.action_name}`" if kontroller
        text += "\n"
      end

      [text, data]
    end

    def fields(clean_message, backtrace, data)
      fields = [
        { title: 'Exception', value: clean_message },
        { title: 'Hostname', value: Socket.gethostname }
      ]

      if exception.backtrace
        backtrace = clean_backtrace(exception, options[:backtrace_cleaner]) || []
        formatted_backtrace = "```#{backtrace.first(@backtrace_lines).join("\n")}```"
        fields.push({ title: 'Backtrace', value: formatted_backtrace })
      end

      unless data.empty?
        deep_reject(data, @ignore_data_if) if @ignore_data_if.is_a?(Proc)
        data_string = data.map { |k, v| "#{k}: #{v}" }.join("\n")
        fields << { title: 'Data', value: "```#{data_string}```" }
      end

      fields.concat(@additional_fields) if @additional_fields
      fields.concat(options[:additional_fields]) if options[:additional_fields]

      attchs = [color: @color, text: text, fields: fields, mrkdwn_in: %w(text fields)]

      if valid?(current_channel)
        send_notice(exception, options, clean_message, @message_opts.merge(attachments: attchs)) do |msg, message_opts|
          notifier.ping '', message_opts
        end
      end

      fields
    end

    protected

    def valid?(current_channel)
      !notifier_for(current_channel).nil?
    end

    def deep_reject(hash, block)
      hash.each do |k, v|
        if v.is_a?(Hash)
          deep_reject(v, block)
        end

        if block.call(k, v)
          hash.delete(k)
        end
      end
    end
  end
end
