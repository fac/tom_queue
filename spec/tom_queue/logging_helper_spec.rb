require 'spec_helper'
require 'tempfile'

describe TomQueue::LoggingHelper do

  include TomQueue::LoggingHelper

  let(:file) { Tempfile.new("logfile") }
  let(:logger) { Logger.new(file.path) }
  let(:output) { file.flush; File.read(file.path) }

  before do
    logger.formatter = ::Logger::Formatter.new
    TomQueue.logger = logger
  end

  describe "basic behaviour" do

    it "should emit a debug message passed as an argument" do
      debug "Simple to compute"
      output.should =~ /^D.+Simple to compute$/
    end

    it "should emit an info message passed as an argument" do
      info "Simple to compute"
      output.should =~ /^I.+Simple to compute$/
    end

    it "should emit a warning message passed as an argument" do
      warn "Simple to compute"
      output.should =~ /^W.+Simple to compute$/
    end

    it "should emit an error message passed as an argument" do
      error "Simple to compute"
      output.should =~ /^E.+Simple to compute$/
    end

    it "should emit a debug message returned from the block" do
      debug { "Expensive to compute" }
      output.should =~ /^D.+Expensive to compute$/
    end

    it "should emit a info message returned from the block" do
      info { "Expensive to compute" }
      output.should =~ /^I.+Expensive to compute$/
    end

    it "should emit a warn message returned from the block" do
      warn { "Expensive to compute" }
      output.should =~ /^W.+Expensive to compute$/
    end

    it "should emit a error message returned from the block" do
      error { "Expensive to compute" }
      output.should =~ /^E.+Expensive to compute$/
    end
  end

  describe "when the log level is info" do
    before do
      logger.level = Logger::INFO
    end

    it "should not yield the debug block" do
      @called = false
      debug { @called = true }
      @called.should be_false
    end
  end

  describe "when the log level is warn" do
    before do
      logger.level = Logger::WARN
    end

    it "should not yield the debug block" do
      @called = false
      debug { @called = true }
      @called.should be_false
    end
    it "should not yield the info block" do
      @called = false
      info { @called = true }
      @called.should be_false
    end
  end

  describe "when the log level is error" do
    before do
      logger.level = Logger::ERROR
    end

    it "should not yield the debug block" do
      @called = false
      debug { @called = true }
      @called.should be_false
    end
    it "should not yield the info block" do
      @called = false
      info { @called = true }
      @called.should be_false
    end
    it "should not yield the warn block" do
      @called = false
      warn { @called = true }
      @called.should be_false
    end
  end

  describe "when TomQueue.logger is nil" do
    before do
      TomQueue.logger = nil
    end
    it "should not yield the debug block" do
      @called = false
      debug { @called = true }
      @called.should be_false
    end
    it "should not yield the info block" do
      @called = false
      info { @called = true }
      @called.should be_false
    end
    it "should not yield the warn block" do
      @called = false
      warn { @called = true }
      @called.should be_false
    end
    it "should not yield the error block" do
      @called = false
      error { @called = true }
      @called.should be_false
    end
    it "should drop debug messages silently" do
      debug "Message"
    end
    it "should drop info messages silently" do
      info "Message"
    end
    it "should drop warn messages silently" do
      warn "Message"
    end
    it "should drop error messages silently" do
      error "Message"
    end
  end

  

end

