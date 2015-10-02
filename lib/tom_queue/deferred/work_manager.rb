require "set"
require "thread"

require "tom_queue/deferred/work"

module TomQueue

  # Internal: This is an internal class that oversees the delay of "deferred"
  # work, that is, work with a future :run_at value.
  #
  # DefferedWorkManager#new takes a prefix value to set up RabbitMQ exchange
  # and queue for deferred jobs
  #
  # Work is also pushed to this manager by the QueueManager when it needs to be deferred.
  #
  # For the purpose of listening to the deferred jobs queue and handling jobs when they're
  # ready to run DeferredWorkManager::start is intended to run AS A SEPARATE PROCESS
  #
  # Internally, this class opens a separate AMQP channel (without a prefetch limit) and
  # leaves all the deferred messages in an un-acked state. The process checks periodically
  # if the next message is ready to run, at which point the message is
  # published to the regular jobs queue by QueueManager, and at some point will be processed by a worker.
  #
  # If the host process of this manager dies for some reason, the broker will re-queue the
  # un-acked messages onto the deferred queue, to be re-popped by another worker in the pool.
  #
  module Deferred
    class WorkManager

      include LoggingHelper

      attr_accessor :prefix, :queue, :consumer, :deferred_set, :out_manager, :channel, :timeout, :deferred_set_mutex

      def initialize(prefix = nil)
        @prefix = prefix || TomQueue.default_prefix
        @prefix || raise(ArgumentError, 'prefix is required')
        setup_amqp
        @deferred_set = SortedSet.new
        @deferred_set_mutex = Mutex.new
        @out_manager = QueueManager.new(prefix)
        @timeout = 2
      end


      # Internal: Creates the bound exchange and queue for deferred work on the provided channel
      def setup_amqp
        @channel = TomQueue.bunny.create_channel
        @channel.prefetch(0)

        @exchange = channel.fanout("#{prefix}.work.deferred",
          :durable     => true,
          :auto_delete => false)

        @queue = channel.queue("#{prefix}.work.deferred",
          :durable     => true,
          :auto_delete => false).bind(@exchange.name)
      end

      # Internal: This is called on a bunny internal work thread when
      # a new message arrives on the deferred work queue.
      #
      # response - the AMQP response object from Bunny
      # headers  - (Hash) a hash of headers associated with the message
      # payload  - (String) the message payload
      #
      def schedule(response, headers, payload)
        run_at = Time.at(headers[:headers]['run_at'])

        # add the work to the priority queue
        deferred_set_mutex.synchronize do
          deferred_set << Work.new(run_at, [response, headers, payload])
        end
      rescue StandardError => e
        r = TomQueue.exception_reporter
        r && r.notify(e)
      end

      def start
        debug "[DeferredWorkManager] Deferred process starting up"

        @consumer = queue.subscribe(:ack => true, &method(:schedule))

        # This is the core event loop - we block on the deferred set to return messages
        # (which have been scheduled by the AMQP consumer). If a message is returned
        # then we re-publish the messages to our internal QueueManager and ack the deferred
        # message
        while true
          deferred_set_mutex.synchronize do
            work = deferred_set.first

            if work
              if work.run_at < Time.now.to_f
                response, headers, payload = work.job

                deferred_set.delete(work)
                headers[:headers].delete('run_at')
                out_manager.publish(payload, headers[:headers])
                channel.ack(response.delivery_tag)
              end
            end
          end

          sleep timeout
        end
      rescue StandardError => e
        error e
        reporter = TomQueue.exception_reporter
        reporter && reporter.notify($!)
      end

      def stop
        consumer && consumer.cancel
        channel && channel.close
      end
    end
  end
end
