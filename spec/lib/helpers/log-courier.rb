# encoding: utf-8

# Copyright 2014 Jason Woods.
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

# Common helpers for testing the courier
shared_context 'Helpers_Log_Courier' do
  before :all do
    # Just in case of a remnant from a previous run that did not cleanup
    File.unlink('.log-courier') if File.file?('.log-courier')
  end

  before :each do
    @config = File.open(File.join(TEMP_PATH, 'config'), 'w')

    @log_courier = nil
  end

  after :each do
    shutdown

    File.unlink(@config.path) if File.file?(@config.path)

    # This is important or the state will not be clean for the following test
    File.unlink('.log-courier') if File.file?('.log-courier')
  end

  def startup(args = {})
    args = {
      config:  nil,
      args:    '',
      stdin:   false,
      verbose: true
    }.merge!(args)

    config = args[:config]

    # A standard configuration when we don't want anything special
    if config.nil?
      config = <<-config
      {
        "network": {
          "ssl ca": "#{@ssl_cert.path}",
          "servers": [ "127.0.0.1:#{server_port}" ],
          "timeout": 15,
          "reconnect": 1
        },
        "files": [
          {
            "paths": [ "#{TEMP_PATH}/logs/log-*" ]
          }
        ]
      }
      config
    end

    if args[:verbose]
      puts "Starting Log Courier with configuration:\n#{config}"
    else
      puts 'Starting Log Courier'
    end

    _write_config config

    if args[:stdin]
      @log_courier_mode = 'r+'
    else
      @log_courier_mode = 'r'
    end

    # Start LSF
    @log_courier = IO.popen("bin/log-courier -config #{@config.path}" + (args[:args].empty? ? '' : ' ' + args[:args]), @log_courier_mode)

    # Start a thread to flush the STDOUT from the pipe
    log_courier = @log_courier
    @log_courier_reader = Thread.new do
      loop do
        line = log_courier.gets
        break if line.nil?
        puts ':' + line
      end
      puts ':END'
    end

    # Needs some time to startup - to ensure when we create new files AFTER this, they are not detected during startup
    sleep STARTUP_WAIT_TIME
  end

  def reload(config)
    puts "Reloading with configuration:\n#{config}"
    _write_config config

    Process.kill('HUP', @log_courier.pid)
  end

  def _write_config(config)
    if @config.closed?
      # Reopen the config and rewrite it
      @config.reopen(@config.path, 'w')
    end
    @config.puts config
    @config.close
  end

  def shutdown
    puts 'Shutting down Log Courier'
    return if @log_courier.nil?
    terminated = false
    # Send SIGTERM
    Process.kill('TERM', @log_courier.pid)
    begin
      Timeout.timeout(30) do
        # Close and wait
        @log_courier.close_write if @log_courier_mode == 'r+'
        @log_courier_reader.join
      end
      terminated = true
    rescue Timeout::Error
      puts "Log-courier hung during shutdown, sending QUIT signal"
    end
    unless terminated
      # Force a stacktrace
      Process.kill('QUIT', @log_courier.pid)
      @log_courier_reader.join
    end
    @log_courier = nil
    @log_courier_reader = nil
  end
end
