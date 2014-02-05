require "spec_helper"

require "tom_queue/runner"

module TomQueue
  describe Runner do
    describe "#start" do
      it "daemonizes consumer" do
        consumer = double(:consumer)
        daemon_builder = double(:daemon_builder)
        daemon = double(:daemon)

        runner = TomQueue::Runner.new(
          :consumer       => consumer,
          :daemon_builder => daemon_builder
        )

        expect(daemon_builder).to receive(:call).with(
          nil,
          consumer,
          {
            :worker_type => "thread",
            :workers     => 2
          }
        ).and_return(daemon)

        expect(daemon).to receive(:run)

        runner.start
      end
    end
  end
end
