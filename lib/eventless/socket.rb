require 'socket'
require 'fcntl'
module Eventless
  RealBasicSocket = ::BasicSocket
  RealSocket = ::Socket
  RealIPSocket = ::IPSocket
  RealTCPSocket = ::TCPSocket
  RealTCPServer = ::TCPServer

  # We will do UDP sockets, but I haven't looked at them yet:
  RealUDPSocket = ::UDPSocket
  RealUDPServer = ::UDPServer

  # I haven't looked at this yet:
  # RealSOCKSSocket = ::SOCKSSocket

  # Should we even support these?
  # RealUNIXSocket = ::UNIXSocket
  # RealUNIXServer = ::UNIXServer

  Object.class_eval do
    remove_const(:BasicSocket)
    remove_const(:Socket)
    remove_const(:IPSocket)
    remove_const(:TCPSocket)
    remove_const(:TCPServer)

    const_set(:BasicSocket, Eventless::BasicSocket)
    const_set(:Socket, Eventless::Socket)
    const_set(:IPSocket, Eventless::IPSocket)
    const_set(:TCPSocket, Eventless::TCPSocket)
    const_set(:TCPServer, Eventless::TCPServer)
  end

  class Eventless::BasicSocket
    class << self
      alias_method :for_fd, :new
    end
    
    def initialize(*args)
      @socket = Eventless.const_get("Real#{self.class}").for_fd(*args)
    end

    ##############
    # Sending data
    def syswrite(*args)
      STDERR.puts "syswrite"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        result = @socket.write_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitWritable, Errno::EINTR
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:write, self))
        retry
      end

      result
    end

    def write(str)
      STDERR.puts "write"

      str = str.to_s
      written = 0

      loop do
        written += syswrite(str[written, str.length])
        break if written == str.length
      end

      str.length
    end

    def sendmsg(*args)
      STDERR.puts "sendmsg"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        result = @socket.sendmsg_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitWritable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:write, self))
        retry
      end

      result
    end

    def print(*objs)
      objs[0] = $_ if objs.size == 0

      objs.each_with_index do |obj, i|
        write($,) if $, and i > 0
        write(obj)
      end

      write($\) if $\ and objs.size > 0
    end

    ################
    # Receiving data
    BUFFER_LENGTH = 128*1024

    def sysread(*args)
      STDERR.puts "sysread"
      buffer = ""
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        buffer << @socket.read_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitReadable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:read, self))
        retry
      end

      buffer
    end

    def readpartial(length=nil, buffer=nil)
      raise ArgumentError if !length.nil? && length < 0
      STDERR.puts "readpartial"

      buffer = "" if buffer.nil?
      if byte_buffer.length >= length
        buffer << byte_buffer.slice!(0, length)
      elsif byte_buffer.length > 0
        buffer << byte_buffer.slice!(0, byte_buffer.length)
      else
        buffer << sysread(length)
      end

      buffer
    end

    def read(length=nil, buffer=nil)
      raise ArgumentError if !length.nil? && length < 0
      STDERR.puts "read" unless length == 1

      return "" if length == 0
      buffer = "" if buffer.nil?

      if length.nil?
        loop do
          begin
            buffer << sysread(BUFFER_LENGTH)
          rescue EOFError
            break
          end
        end
      else
        if byte_buffer.length >= length
          return byte_buffer.slice!(0, length)
        elsif byte_buffer.length > 0
          buffer << byte_buffer.slice!(0, byte_buffer.length)
        end

        remaining = length - buffer.length
        while buffer.length < length && remaining > 0
          begin
            buffer << sysread(remaining > BUFFER_LENGTH ? remaining : BUFFER_LENGTH)
            remaining = length - buffer.length
          rescue EOFError
            break
          end
        end
      end

      return nil if buffer.length == 0
      if length and buffer.length > length
        byte_buffer << buffer.slice!(length, buffer.length)
      end

      buffer
    end

    def readchar
      c = read(1)
      raise EOFError if c.nil?
      c
    end

    def getc
      read(1)
    end

    def gets(sep=$/, limit=nil)
      STDERR.puts "gets"

      if sep.kind_of? Numeric and limit.nil?
        limit = sep
        sep = $/
      end

      sep = "\n\n" if sep == ""
      str = ""
      if sep.nil?
        str = read
      else
        while str.index(sep).nil?
          c = read(1)
          break if c.nil?
          str << c
          break if not limit.nil? and str.length == limit
        end
      end

      $_ = str
      str
    end

    def recv(*args)
      STDERR.puts "recv"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        mesg = @socket.recv_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitReadable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:read, self))
        retry
      end

      mesg
    end

    def recvmsg(*args)
      STDERR.puts "recvmsg"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        msg = @socket.recvmsg_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitReadable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:read, self))
        retry
      end

      msg
    end

    private

    def socket=(socket)
      @socket = socket
    end

    # XXX: eventually this may have a second command called timeout
    def wait(watcher)
      Eventless.loop.attach(watcher)
      begin
        Eventless.loop.transfer
      ensure
        watcher.detach
      end
    end

    def byte_buffer
      @buffer ||= ""
    end

    def byte_buffer=(buffer)
      @buffer = buffer
    end
  end

  class Eventless::Socket < Eventless::BasicSocket

    def initialize(*args)
      @socket = Eventless.const_get("Real#{self.class}").new(*args)
    end

    def connect(*args)
      STDERR.puts "connect"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        @socket.connect_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitWritable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        #STDERR.puts "connect: about to sleep"
        wait(Eventless.loop.io(:write, self))
        retry
      rescue Errno::EISCONN
        @socket.fcntl(Fcntl::F_SETFL, flags)
      end
      #STDERR.puts "Connected!"
    end

    def accept(*args)
      STDERR.puts "accept"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        sock_pair = @socket.accept_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitReadable, Errno::EINTR
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:read, self))
        retry
      end

      sock_pair
    end

    def recvfrom(*args)
      STDERR.puts "recvfrom"
      begin
        flags = @socket.fcntl(Fcntl::F_GETFL, 0)
        pair = @socket.recvfrom_nonblock(*args)
        @socket.fcntl(Fcntl::F_SETFL, flags)
      rescue IO::WaitReadable
        @socket.fcntl(Fcntl::F_SETFL, flags)
        wait(Eventless.loop.io(:read, self))
        retry
      end

      pair
    end

  end

  AF_MAP = {}
  RealSocket.constants.grep(/^AF_/).each do |c|
    AF_MAP[RealSocket.const_get(c)] = c.to_s
  end

  class Eventless::IPSocket < Eventless::BasicSocket
    def peeraddr(reverse_lookup=nil)
      reverse_lookup = should_reverse_lookup?(reverse_lookup)
      addr = @socket.remote_address

      name_info = reverse_lookup ? addr.getnameinfo[0] : addr.ip_address

      [AF_MAP[addr.afamily], addr.ip_port, name_info, addr.ip_address]
    end

    private
    def should_reverse_lookup?(reverse_lookup)
      case reverse_lookup
      when true, :hostname
        true
      when false, :numeric
        false
      when nil
        not @socket.do_not_reverse_lookup
      else
        if reverse_lookup.kind_of? Symbol
          raise TypeError, "wrong argument type #{reverse_lookup.class} (expected Symbol)"
        end

        raise ArgumentError, "invalid reverse_lookup flag: #{reverse_lookup}"
      end
    end
  end

  class Eventless::TCPSocket < Eventless::IPSocket
    class << self
      alias_method :open, :new
    end

    def initialize(remote_host, remote_port, local_host=nil, local_port=nil)
      @socket = Socket.new(:INET, :STREAM)
      @socket.connect(Socket.pack_sockaddr_in(remote_port, remote_host))

      if local_host && local_port
        @socket.bind(Socket.pack_sockaddr_in(local_port, local_host))
      end
    end

  end

  class Eventless::TCPServer < Eventless::TCPSocket
    class << self
      alias_method :open, :new
    end

    def initialize(hostname=nil, port)
      # XXX: addrinfo.foreach will block on dns resolution
      # need a thread pool to make it work properly
      Addrinfo.foreach(hostname, port, nil, :STREAM, nil, Socket::AI_PASSIVE) do |ai|
        begin
          @socket = Socket.new(ai.afamily, ai.socktype, ai.protocol)
          @socket.setsockopt(:SOCKET, :REUSEADDR, true)
          @socket.bind(ai)
        rescue
          @socket.close
        else
          break
        end
      end

      @socket.listen(5)
    end

    def accept
      TCPSocket.for_fd(@socket.accept[0].fileno)
    end
  end
end
