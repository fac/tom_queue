TomQueue
=========

TomQueue is a replacement for the [Delayed::Job](https://github.com/collectiveidea/delayed_job) gem, which sends

Why?
----

At FreeAgent, we have historically used Delayed::Job to manage asynchronous work, however we've found that MySQL performs particularly poorly when the work queued gets large (i.e. 10k+). In fact, the larger the queue of work gets, the *slower* the query to pull the next job! The more Delayed:::Job workers that are running the bigger problem it becomes.

We decided that we'd like to retain database as the "source of truth", and all our existing jobs use Delayed::Job logic for handling failed jobs, managing locking etc. All we needed was a more suitable queue-server. This is where TomQueue comes in.

In order to keep the changes to the existing codebase as minimal as possible, we've aliased the TomQueue namespace (`Delayed = TomQueue`).

Great, how do I use it?
-----------------------

Ok, first you need an RabbitMQ server [installed](https://www.rabbitmq.com/download.html) and running. It also helps to have [Management Plugin](https://www.rabbitmq.com/management.html) enabled. It'll run RabbitMQ web interface at `http://localhost:15672`.

Once you have this, open your projects `Gemfile` and add the entry:

    gem 'tom_queue'

Then, the next step is to add the generic TomQueue configuration - we stuff this into a Rails initializer:

``` ruby
require 'tom_queue'

TomQueue.priority_map[1] = TomQueue::BULK_PRIORITY
TomQueue.priority_map[2] = TomQueue::LOW_PRIORITY
TomQueue.priority_map[4] = TomQueue::NORMAL_PRIORITY
TomQueue.priority_map[3] = TomQueue::HIGH_PRIORITY

# Make sure internal exceptions in TomQueue make it to Hoptoad (or Honeybadger or whatever)!
TomQueue.exception_reporter = ErrorService
TomQueue.logger = Rails.logger
```

The priority map maps TomQueue's numerical priority values to discrete priority levels, of BULK, LOW, NORMAL and HIGH, since we can't support arbitrary priorities. Any un-mapped values are presumed to be NORMAL. See below for further discussion on how job-priority works.

The `logger` is a bog-standard `Logger` object that, when set, receives warnings and errors from the TomQueue internals, useful for figuring out what is going on and when things go wrong. The `exception_reporter`, if set, should respond to `notify(exception)` and will receive any exceptions caught during the job lifecycle. If this isn't set, exceptions will just be logged.

Now you need to configure TomQueue in your Rails environments and wire in the AMQP broker configuration for them. In, for example, `config/environments/production.rb` add the lines:

```ruby
AMQP_CONFIG = {
  :host     => 'localhost',
  :port     => 5672,
  :vhost    => '/',
  :ssl      => false,
  :user     => 'guest',
  :password => 'guest',
  :read_timeout => 10,
  :write_timeout => 10,
}

TomQueue.bunny = Bunny.new(AMQP_CONFIG)
TomQueue.bunny.start
TomQueue.default_prefix = "tomqueue-production"
```

Replacing `AMQP_CONFIG` with the necessary Bunny configuration for your environment. The `default_prefix` is prefixed onto all AMQP exchanges and queues created by tom-queue, which can be a handy name-space.

Ok, so what happens now?
------------------------

```ruby
class MyJob
  def process
    # Do Something
  end
end

Delayed::Job.enqueue(MyJob.new)
```

Job classes work in the same way as Delayed Job - they _must_ respond to `process`, and can optionally have an `enqueue` method which will be called in `TomQueue::Enqueue`, and `before`, `after`, `success`, `error`, and `failure` methods which will be called by the `TomQueue::Worker`.

Enqueueing a delayed job style piece of work will persist it to the database in a `TomQueue::Persistence::Model` (identical to the original `Delayed::Backend:ActiveRecord::Job` class). Once this is committed it publishes a message to AMQP with the job id and checksum to be picked up by any worker process.

So, how does this thing work?
-----------------------------

TomQueue has two stacks - `TomQueue::Enqueue::Stack` for pushing work into the database and onto AMQP, and `TomQueue::Worker::Stack`. Each of these stacks has multiple layers, each responsible for a discrete part of the process, in much the same way as Rack middleware.

TomQueue::Enqueue::Stack
* DelayedJob is responsible for persisting DJ style work to the database if necessary, and passing it on to....
* Publish which takes the work and publishes the notification to AMQP.

TomQueue::Worker::Stack
* ErrorHandling wraps the stack and rescues any exceptions which might be thrown when executing a job
* Pop retrieves the next piece of work from AMQP and passes it down the stack, acking or nacking the work depending on the result
* DelayedJob acquires and locks the database record for the work, passes it down the stack, then updates the record status (passthru if it is not a DJ compatible work unit)
* Timeout wraps the job execution in a timeout block
* Invoke executes the job

Each of these stacks interacts with AMQP via a QueueManager, which in turn leans on Bunny.

### Deferred jobs

Some jobs have to be run at some point in the future. To separate the jobs that should be run immediately from the "deferred" jobs TomQueue has a separate deferred queue and a **separate process** to manage these jobs.

When the job is published to the queue `TomQueue::QueueManager` decides whether it should be published to one of the priority queues or to the deferred queue.

Note: It gets confusing sometimes, so it's important to remember that RabbitMQ messages don't get published to the queue. They get published to the **exchange** and then they're later **routed** to the queue. E.g. TomQueue uses one exchange per all 4 priority queues.

If job's `run_at` attribute is set in the future it ends up in the deferred queue.

There's a special process that is started separately from all DJ workers (but at the same time) that only listens to the deferred queue. It reads all the messages that come to the queue and holds them in memory in a sorted by `run_at` queue. When the job's time comes the process publishes the job to the "normal" exchange.

If you look at the deferred queue in the web interface when this "deferred process" is running you'll noticed that messages in that queue are ["Unacked"](https://www.rabbitmq.com/reliability.html). It means that consumer (deferred process) received a message but didn't send an acknowledgment for it. In the semantics of the deferred process it means that job is waiting for the time to run in deferred process's memory. We do it this way to account for the case when deferred process dies before dispatching all deferred jobs. In that case all the unacknowledged messages just get re-queued to the deferred queue. `TomQueue::DeferredWorkManager` class is responsible for managing deferred jobs and runs in a separate process.

What about when I'm developing?
-------------------------------

/shrug Needs work.

You can also, of course, run a development AMQP broker and wire it up as in production to try it all out.

Cool. Is it safe to use?
------------------------

Probably...

Do let us know if you find any bugs or improve it (or just manage to get it to work!!) open an issue or pull-request here or alternatively ping me a mail at thomas -at- freeagent -dot- com
