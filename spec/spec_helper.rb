require "rubygems"
require "bundler/setup"

# To help produce better bug reports in Rubinius
if RUBY_ENGINE == "rbx"
  # $DEBUG = true # would be nice if this didn't fail ... :(
  require "rspec/matchers"
  require "rspec/matchers/built_in/be"
end

# Require in order, so both CELLULOID_TEST and CELLULOID_DEBUG are true
require "celluloid/rspec"
require "celluloid/essentials"

$CELLULOID_DEBUG = true

# Require but disable, so it has to be explicitly enabled in tests
require "celluloid/probe"
$CELLULOID_MONITORING = false
Specs.reset_probe(nil)

Celluloid.shutdown_timeout = 1

Dir["./spec/support/*.rb", "./spec/shared/*.rb"].map { |f| require f }

RSpec.configure do |config|
  config.filter_run focus: true unless Nenv.ci?

  config.run_all_when_everything_filtered = true
  config.disable_monkey_patching!
  config.profile_examples = 3

  Specs.configure(config)

  config.before(:suite) do
    Specs.stub_out_class_method(Celluloid::Internals::Logger, :crash) do |*args|
      _name, ex = *args
      fail "Unstubbed Logger.crash() was called:\n  crash(\n    #{args.map(&:inspect).join(",\n    ")})"\
        "\nException backtrace: \n  (#{ex.class}) #{ex.backtrace * "\n  (#{ex.class}) "}"
    end
  end

  config.before(:each) do |example|
    @fake_logger = Specs::FakeLogger.new(Celluloid.logger, example.description)
    stub_const("Celluloid::Internals::Logger", @fake_logger)
  end

  config.around do |ex|
    ex.run
    if @fake_logger.crashes?
      crashes = @fake_logger.crashes.map do |args, call_stack|
        msg, ex = *args
        "\n** Crash: #{msg.inspect}(#{ex.inspect})\n  Backtrace:\n    (crash) #{call_stack * "\n    (crash) "}"\
          "\n** Crash: \"Actor crashed!\"(#{ex.inspect})\n  Backtrace:\n    (crash) #{call_stack * "\n    (crash) "}"\
          "\n  Exception Backtrace (#{ex.inspect}):\n    (ex) #{ex.backtrace * "\n    (ex) "}"
      end.join("\n")

      fail "Actor crashes occurred (please stub/mock if these are expected): #{crashes}"
    end
    @fake_logger = nil
  end

  config.around do |ex|
    Celluloid.actor_system = nil

    Specs.assert_no_loose_threads(ex.description) do
      Specs.reset_class_variables(ex.description) do
        ex.run
      end
    end
  end

  config.around actor_system: :global do |ex|
    # Needed because some specs mock/stub/expect on the logger
    Celluloid.logger = Specs.logger

    Celluloid.boot
    ex.run
    Celluloid.shutdown
  end

  config.around actor_system: :within do |ex|
    Celluloid::Actor::System.new.within do
      ex.run
    end
  end

  config.filter_gems_from_backtrace(*%w(rspec-expectations rspec-core rspec-mocks rspec-logsplit rubysl-thread rubysl-timeout))

  config.mock_with :rspec do |mocks|
    mocks.verify_doubled_constant_names = true
    mocks.verify_partial_doubles = true
  end

  config.around(:each) do |example|
    # Needed because some specs mock/stub/expect on the logger
    Celluloid.logger = Specs.logger
    example.run
  end
end
