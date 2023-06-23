require "json"

module GCR
  Error = Class.new(StandardError)
  ConfigError = Class.new(Error)
  RunningError = Class.new(Error)
  NoRecording = Class.new(Error)
  NoCassette = Class.new(Error)

  # Ignore these fields when matching requests.
  #
  # *fields - String field names (eg. "token").
  #
  # Returns nothing.
  def ignore(*fields)
    ignored_fields.concat(fields.map(&:to_s))
  end

  # Fields that are ignored when matching requests.
  #
  # Returns an Array of Strings.
  def ignored_fields
    @ignored_fields ||= []
  end

  # Specify where GCR should store cassettes.
  #
  # path - The String path to a directory.
  #
  # Returns nothing.
  def cassette_dir=(path)
    raise RunningError, "cannot configure GCR within #with_cassette block" if @running
    @cassette_dir = path
  end

  # Where GCR stores cassettes.
  #
  # Returns a String path to a directory. Raises ConfigError if not configured.
  def cassette_dir
    @cassette_dir || (raise ConfigError, "no cassette dir configured")
  end

  def reset_stubs
    @stub = nil
    @stubs = nil
  end

  # Specify the stub to intercept calls to.
  #
  # stub - A GRPC::ClientStub instance.
  #
  # Returns nothing.
  def stub=(stub)
    raise RunningError, "cannot configure GCR within #with_cassette block" if @running
    @stub = stub
    (@stubs ||= Set.new) << stub
  end

  # The stub that is being mocked.
  #
  # Returns a A GRPC::ClientStub instance. Raises ConfigError if not configured.
  def stub
    @stub || (raise ConfigError, "no stub configured")
  end

  def stubs
    @stubs || (raise ConfigError, "no stubs configured")
    @stubs.to_a
  end
  
  def insert(name)
    @cassette = Cassette.new(name)
    if @cassette.exist?
      @cassette.start_playing
    else
      @cassette.start_recording
    end
  end

  def remove
    if @cassette.exist?
      @cassette.stop_playing
    else
      @cassette.stop_recording
    end
    @cassette = nil
  end

  def cassette
    @cassette
  end

  # If a cassette with the given name exists, play that cassette for the
  # provided block. Otherwise, record a cassette with the provided block.
  #
  # Returns nothing.
  def with_cassette(name, &blk)
    @cassette = Cassette.new(name)
    if @cassette.exist?
      @cassette.play(&blk)
    else
      @cassette.record(&blk)
    end
  ensure
    @cassette = nil
  end

  extend self
end

require "gcr/cassette"
require "gcr/request"
require "gcr/response"
