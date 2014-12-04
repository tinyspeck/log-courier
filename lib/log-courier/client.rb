# encoding: utf-8

# Copyright 2014 Jason Woods.
#
# This file is a modification of code from Logstash Forwarder.
# Copyright 2012-2013 Jordan Sissel and contributors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'log-courier/event_queue'
require 'multi_json'
require 'thread'
require 'zlib'

class NativeException; end

module LogCourier
  class ShutdownSignal < StandardError; end
  class ProtocolError < StandardError; end

  # Describes a pending payload
  class PendingPayload
    attr_accessor :ack_events
    attr_accessor :events
    attr_accessor :nonce
    attr_accessor :data

    attr_accessor :previous
    attr_accessor :next

    def initialize(options = {})
      @ack_events = 0

      options.each do |k, v|
        fail ArgumentError unless self.respond_to?(k)
        instance_variable_set "@#{k}", v
      end
    end
  end

  # Implementation of a single client connection
  class Client
    def initialize(options = {})
      @options = {
        logger:       nil,
        spool_size:   1024,
        idle_timeout: 5
      }.merge!(options)

      @logger = @options[:logger]
      @logger['plugin'] = 'output/courier'

      require 'log-courier/client_tls'
      @client = ClientTls.new(@options)

      # Load the json adapter
      @json_adapter = MultiJson.adapter.instance

      @event_queue = EventQueue.new @options[:spool_size]
      @pending_payloads = {}
      @first_payload = nil
      @last_payload = nil

      # Start the spooler which will collect events into chunks
      @send_ready = false
      @send_mutex = Mutex.new
      @send_cond = ConditionVariable.new
      @spooler_thread = Thread.new do
        run_spooler
      end

      @pending_ping = false

      # Start the IO thread
      @io_control = EventQueue.new 1
      @io_thread = Thread.new do
        run_io
      end
    end

    def publish(event)
      # Pass the event into the spooler
      @event_queue << event
      return
    end

    def shutdown
      # Raise a shutdown signal in the spooler and wait for it
      @spooler_thread.raise ShutdownSignal
      @io_thread.raise ShutdownSignal
      @spooler_thread.join
      @io_thread.join
      return
    end

    private

    def run_spooler
      loop do
        spooled = []
        next_flush = Time.now.to_i + @options[:idle_timeout]

        # The spooler loop
        begin
          loop do
            event = @event_queue.pop next_flush - Time.now.to_i
            spooled.push(event)
            break if spooled.length >= @options[:spool_size]
          end
        rescue TimeoutError
          # Hit timeout but no events, keep waiting
          next if spooled.length == 0
        end

        # Pass through to io_control but only if we're ready to send
        @send_mutex.synchronize do
          @send_cond.wait(@send_mutex) unless @send_ready
          @send_ready = false
          @io_control << ['E', spooled]
        end
      end
      return
    rescue ShutdownSignal
      return
    end

    def run_io
      # TODO: Make keepalive configurable?
      @keepalive_timeout = 1800

      # TODO: Make pending payload max configurable?
      max_pending_payloads = 100

      retry_payload = nil

      can_send = true

      loop do
        # Reconnect loop
        @client.connect @io_control

        reset_keepalive

        # Capture send exceptions
        begin
          # IO loop
          loop do
            catch :keepalive do
              begin
                action = @io_control.pop @keepalive_next - Time.now.to_i

                # Process the action
                case action[0]
                when 'S'
                  # If we're flushing through the pending, pick from there
                  unless retry_payload.nil?
                    # Regenerate data if we need to
                    retry_payload.data = buffer_jdat_data(retry_payload.events, retry_payload.nonce) if retry_payload.data == nil

                    # Send and move onto next
                    @client.send 'JDAT', retry_payload.data

                    retry_payload = retry_payload.next
                    throw :keepalive
                  end

                  # Ready to send, allow spooler to pass us something
                  @send_mutex.synchronize do
                    @send_ready = true
                    @send_cond.signal
                  end

                  can_send = true
                when 'E'
                  # If we have too many pending payloads, pause the IO
                  if @pending_payloads.length + 1 >= max_pending_payloads
                    @client.pause_send
                  end

                  # Received some events - send them
                  send_jdat action[1]

                  # The send action will trigger another "S" if we have more send buffer
                  can_send = false
                when 'R'
                  # Received a message
                  signature, message = action[1..2]
                  case signature
                  when 'PONG'
                    process_pong message
                  when 'ACKN'
                    process_ackn message
                  else
                    # Unknown message - only listener is allowed to respond with a "????" message
                    # TODO: What should we do? Just ignore for now and let timeouts conquer
                  end
                when 'F'
                  # Reconnect, an error occurred
                  break
                end
              rescue TimeoutError
                # Keepalive timeout hit, send a PING unless we were awaiting a PONG
                if @pending_ping
                  # Timed out, break into reconnect
                  fail TimeoutError
                end

                # Is send full? can_send will be false if so
                # We should've started receiving ACK by now so time out
                fail TimeoutError unless can_send

                # Send PING
                send_ping

                # We may have filled send buffer
                can_send = false
              end
            end

            # Reset keepalive timeout
            reset_keepalive
          end
        rescue ProtocolError => e
          # Reconnect required due to a protocol error
          @logger.warn 'Protocol error', :error => e.message unless @logger.nil?
        rescue TimeoutError
          # Reconnect due to timeout
          @logger.warn 'Timeout occurred' unless @logger.nil?
        rescue ShutdownSignal
          # Shutdown, break out
          break
        rescue StandardError, NativeException => e
          # Unknown error occurred
          @logger.warn e, :hint => 'Unknown error' unless @logger.nil?
        end

        # Disconnect and retry payloads
        @client.disconnect
        retry_payload = @first_payload

        # TODO: Make reconnect time configurable?
        sleep 5
      end

      @client.disconnect
      return
    end

    def reset_keepalive
      @keepalive_next = Time.now.to_i + @keepalive_timeout
      return
    end

    def generate_nonce
      (0...16).map { rand(256).chr }.join("")
    end

    def send_ping
      # Send it
      @client.send 'PING', ''
      return
    end

    def send_jdat(events)
      # Generate the JSON payload and compress it
      nonce = generate_nonce
      data = buffer_jdat_data(events, nonce)

      # Save the pending payload
      payload = PendingPayload.new(
        :events => events,
        :nonce  => nonce,
        :data   => data
      )

      @pending_payloads[nonce] = payload

      if @first_payload.nil?
        @first_payload = payload
        @last_payload = payload
      else
        @last_payload.next = payload
        @last_payload = payload
      end

      # Send it
      @client.send 'JDAT', payload.data
      return
    end

    def buffer_jdat_data(events, nonce)
      buffer = Zlib::Deflate.new

      # Write each event in JSON format
      events.each do |event|
        buffer_jdat_data_event(buffer, event)
      end

      # Generate and return the message
      nonce + buffer.flush(Zlib::FINISH)
    end

    def buffer_jdat_data_event(buffer, event)
      json_data = @json_adapter.dump(event)

      # Add length and then the data
      buffer << [json_data.length].pack('N') << json_data
      return
    end

    def process_pong(message)
      # Sanity
      fail ProtocolError, "Unexpected data attached to pong message (#{message.length})" if message.length != 0

      # No longer pending a PONG
      @ping_pending = false
      return
    end

    def process_ackn(message)
      # Sanity
      fail ProtocolError, "ACKN message size invalid (#{message.length})" if message.length != 20

      # Grab nonce
      sequence, nonce = message[0...4].unpack('N').first, message[4..-1]

      # Find the payload - skip if we couldn't as it will just a duplicated ACK
      return unless @pending_payloads.key?(nonce)

      payload = @pending_payloads[nonce]

      # Full ACK?
      # TODO: protocol error if sequence too large?
      if sequence >= payload.events.length
        @client.resume_send if @client.send_paused?

        @pending_payloads.delete nonce
        payload.previous.next = payload.next
      else
        # Partial ACK - only process if something was actually processed
        if sequence > payload.ack_events
          payload.ack_events = sequence
          payload.events = payload.events[0...sequence]
          payload.data = nil
        end
      end
      return
    end
  end
end
