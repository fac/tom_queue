module TomQueue
  module Enqueue
    class DelayedJob < TomQueue::Stack::Layer
      include LoggingHelper

      # Public: For Delayed Job compatible work units, persist them to the
      # database and substitutes the work for the now persisted job
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns the persisted job (if for performable objects) or modified [work, options]
      def call(work, options)
        if performable?(work)
          build(work, options).tap do |job|
            # Run the work unit's :enqueue lifecycle hook if present
            TomQueue::Worker.lifecycle.run_callbacks(:enqueue, job) do
              job.save!
              debug "[#{self.class.name}] Created job #{job.id}"
              job.hook(:enqueue)
              chain.call(job, options)
            end
          end
        else
          chain.call(work, options)
        end
      end

      private

      # Private: Is this a Delayed Job compatible work unit?
      #
      # work - the work unit being enqueued
      #
      # Returns boolean
      def performable?(work)
        work.respond_to?(:perform)
      end

      # Private: Build the Delayed Job compatible persistence model
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns a non-persisted model instance
      def build(work, options)
        TomQueue::Persistence::Model.new(attributes(work, options)).tap do |j|
          j.payload_object = work
        end
      end

      # Private: Build attributes to be persisted on the model
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns a Hash
      def attributes(work, options)
        options.with_indifferent_access.slice(*TomQueue::Persistence::Model::ENQUEUE_ATTRIBUTES).tap do |attrs|
          attrs[:handler] ||= work.to_yaml
        end
      end
    end
  end
end
