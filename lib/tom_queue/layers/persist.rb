module TomQueue
  module Layers
    class Persist < TomQueue::Stack::Layer
      # Public: For Delayed Job compatible work units, persist them to the
      # database and substitutes the work for the now persisted job
      #
      # work - the work unit being enqueued
      # options - Hash of options defining how the job should be run
      #
      # Returns modified [work, options]
      def call(work, options)
        if delayed_job?(work)
          job = build(work, options).tap do |j|
            # Run the work unit's :enqueue lifecycle hook if present
            work.enqueue(j) if work.respond_to?(:enqueue)
          end
          job.save!
          chain.call(job, options)
        else
          chain.call(work, options.merge(job: job))
        end
      end

      private

      # Private: Is this a Delayed Job compatible work unit?
      #
      # work - the work unit being enqueued
      #
      # Returns boolean
      def delayed_job?(work)
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
