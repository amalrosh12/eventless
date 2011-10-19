module Kernel
  alias_method :select_block, :select

  def select(*args)
    Eventless.select(*args)
  end
end

class IO
  class << self
    alias_method :select_block, :select

    def select(*args)
      Eventless.select(*args)
    end
  end
end

module Eventless
  # TODO: Need to implement select with timeout. How do I test it?
  def self.select(read_array, write_array=[], error_array=[], timeout=nil)
    watchers = []
    ready = SelectResults.new

    write_array = [] if write_array.nil?

    #STDERR.puts "about to select", read_array.inspect, write_array.inspect
    STDERR.puts "select"

    begin
      read_array.each do |io|
        watcher = Eventless.loop.io(:read, io) { ready.append_read(io) }
        Eventless.loop.attach(watcher)
        watchers << watcher
      end

      write_array.each do |io|
        watcher = Eventless.loop.io(:write, io) { ready.append_write(io) }
        Eventless.loop.attach(watcher)
        watchers << watcher
      end

      ready.event.wait(timeout)
      return ready.to_read, ready.to_write, []
    ensure
      watchers.each { |w| w.detach }
    end

  end

  class SelectResults
    attr_reader :to_read, :to_write, :event

    def initialize
      @to_read = []
      @to_write = []
      @event = Event.new
    end

    def append_read(io)
      @to_read << io
      @event.set!
    end

    def append_write(io)
      @to_write << io
      @event.set!
    end
  end
end
