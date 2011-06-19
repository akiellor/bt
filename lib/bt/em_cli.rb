require 'eventmachine'

class Ready
 def initialize &callback
    @callback = callback
    @readies = []
    @none = EM::DefaultDeferrable.new
  end

  def next
    callback = @callback
    refresh do |readies|
      if readies.empty?
        @none.succeed
      else
        next_ready = readies.shuffle.shift
        @callback.call next_ready[:commit], next_ready[:stage]
      end
    end
  end

  def none &block
    @none.callback &block
  end

  def refresh &callback
    EM.popen('bin/bt-ready', Process, callback)
  end

  class Process < EM::Connection
    def initialize callback
      @callback = callback
      @readies = []
    end

    def receive_data data
      (@buffer ||= BufferedTokenizer.new).extract(data).each do |line|
        commit, stage = line.split '/'
        @readies << {:commit => commit, :stage => stage}
      end
    end

    def unbind
      @callback.call @readies
    end
  end
end

class Go
 def initialize commit, stage
    @commit = commit
    @stage = stage
    @done = EM::DefaultDeferrable.new
  end

  def done &block
    @done.callback &block
  end

  def build
    @connection = EM.popen("bin/bt-go --commit #{@commit} --stage #{@stage}", Process, @done)
  end

  def stop
    @connection and @connection.close_connection
  end

  class Process < EM::Connection
    def initialize done
      @done = done
    end

   def receive_data data
   end

    def unbind
      @done.succeed
    end
  end
end

class Agent
  def initialize key
    @key = key
    @stop = EM::DefaultDeferrable.new
    @lead = EM::DefaultDeferrable.new
    @done = EM::DefaultDeferrable.new
    @connection = EM.popen("bin/bt-agent #{key}", Process, @stop, @lead)
  end

  def leading &block
    @lead.callback &block
  end

  def stop
    @connection.close_connection
  end

  def stopped &block
    @stop.callback &block
  end

  class Process < EM::Connection
    def initialize stop, lead
      @stop = stop
      @lead = lead
    end

    def receive_data data
      @lead.succeed
    end

    def unbind
      @stop.succeed
    end
  end
end

