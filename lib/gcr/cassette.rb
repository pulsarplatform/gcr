class GCR::Cassette
  VERSION = 2

  attr_reader :reqs

  # Delete all recorded cassettes.
  #
  # Returns nothing.
  def self.delete_all
    Dir[File.join(GCR.cassette_dir, "*.json")].each do |path|
      File.unlink(path)
    end
  end

  # Initialize a new cassette.
  #
  # name - The String name of the recording, from which the path is derived.
  #
  # Returns nothing.
  def initialize(name)
    @path = File.join(GCR.cassette_dir, "#{name}.json")
    @reqs = []
  end

  # Does this cassette exist?
  #
  # Returns boolean.
  def exist?
    File.exist?(@path)
  end

  # Load this cassette.
  #
  # Returns nothing.
  def load
    data = JSON.parse(File.read(@path))

    if data["version"] != VERSION
      raise "GCR cassette version #{data["version"]} not supported"
    end

    @reqs = data["reqs"].map do |req, resp|
      [GCR::Request.from_hash(req), GCR::Response.from_hash(resp)]
    end
  end

  # Persist this cassette.
  #
  # Returns nothing.
  def save
    File.open(@path, "w") do |f|
      f.write(JSON.pretty_generate(
        "version" => VERSION,
        "recorded_at" => Time.now,
        "reqs"    => reqs,
      ))
    end
  end

  # Record all GRPC calls made while calling the provided block.
  #
  # Returns nothing.
  def record(&blk)
    start_recording
    blk.call
  ensure
    stop_recording
  end

  # Play recorded GRPC responses.
  #
  # Returns nothing.
  def play(&blk)
    start_playing
    blk.call
  ensure
    stop_playing
  end

  def start_recording
    GCR.stubs.each do |stub|
      _start_recording(stub)
    end
  end

  def stop_recording
    GCR.stubs.each do |stub|
      _stop_recording(stub)
    end
    save
  end

  def start_playing
    load

    GCR.stubs.each do |stub|
      _start_playing(stub)
    end
  end

  def stop_playing
    GCR.stubs.each do |stub|
      _stop_playing(stub)
    end
  end

  def [](req)
    reqs.find { |r| r == req }
  end

  def []=(req, resp)
    reqs << [req, resp]
  end

  private

  def already_intercepted?(instance)
    instance.method_defined?(:orig_request_response)
  end

  def _start_recording(stub)
    return if already_intercepted?(stub)

    stub.class_eval do
      alias_method :orig_request_response, :request_response

      def request_response(*args, **kwargs)
        raise GCR::NoCassette unless GCR.cassette

        orig_request_response(*args, **kwargs).tap do |resp|
          req = GCR::Request.from_proto(*args, **kwargs)

          return resp unless GCR.cassette.reqs.none? { |recorded_req, _| recorded_req == req }

          # check if our request wants an operation returned rather than the response
          if args.last[:return_op] == true
            # if so, collect the original operation
            operation = resp
            result = operation.execute

            # hack the execute method to return the response we recorded
            resp.define_singleton_method(:execute) { return result }

            # GCR::Response.from_proto(operation)
            GCR.cassette.reqs << [req, GCR::Response.from_proto(result)]
          else
            GCR.cassette.reqs << [req, GCR::Response.from_proto(resp)]
          end
          
          resp
        end
      end
    end
  end

  def _stop_recording(stub)
    return unless already_intercepted?(stub)

    stub.class_eval do
      alias_method :request_response, :orig_request_response

      remove_method :orig_request_response
    end
  end

  def _start_playing(stub)
    return if already_intercepted?(stub)

    stub.class_eval do
      alias_method :orig_request_response, :request_response

      def request_response(*args, **kwargs)
        req = GCR::Request.from_proto(*args, **kwargs)
        record = GCR.cassette.reqs.detect { |recorded_req, _| recorded_req == req }

        raise GCR::NoRecording, "No recording found for #{req}" unless record

        recorded_req, resp = record

        # check if our request wants an operation returned rather than the response
        if args.last[:return_op] == true
          # if so, collect the original operation
          operation = orig_request_response(*args, **kwargs)

          # hack the execute method to return the response we recorded
          operation.define_singleton_method(:execute) { return resp.to_proto }

          # then return it
          return operation
        end

        # otherwise just return the response
        return resp.to_proto
      end
    end
  end

  def _stop_playing(stub)
    return unless already_intercepted?(stub)

    stub.class_eval do
      alias_method :request_response, :orig_request_response

      remove_method :orig_request_response
    end
  end
end
