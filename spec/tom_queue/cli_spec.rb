require "spec_helper"

require "tom_queue/cli"

module TomQueue
  describe CLI do
    describe "#work" do
      it "starts runner" do
        runner = double(:runner)
        runner_instance = double(:runner_instance)

        expect(runner).to receive(:new).and_return(runner_instance)
        expect(runner_instance).to receive(:start)

        TomQueue::CLI.new.work(:runner => runner)
      end
    end

    describe "end-to-end" do
      it "runs consumer inside runner" do
        begin
          work = IO.popen("bundle exec bin/tom_queue work", :err => [:child, :out])
          work.each do |io|
            expect(io).to include("I'm consuming")
            break
          end
        ensure
          Process.kill("TERM", work.pid)
        end
      end
    end
  end
end
