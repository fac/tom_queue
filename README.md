TomQueue
=========

TomQueue is a backend for [Delayed::Job](https://github.com/collectiveidea/delayed_job) gem. TomQueue hooks onto [delayed_job_active_record](https://github.com/collectiveidea/delayed_job_active_record) backend and replaces the mechanism by which Delayed::Job workers acquire jobs. By default Delayed::Job workers poll the database for new jobs. TomQueue replaces "polling" logic with subscription to [RabbitMQ](http://rabbitmq.com) queue. Delayed::Job workers receive a new job as soon as it gets published to the queue.

Why?
----

At FreeAgent, we have always used Delayed::Job to manage asynchronous work and find it still fits our needs well. That said, when it is backed by MySQL, we've found that it performs particularly poorly when the work queued gets large (i.e. 10k+). In fact, the larger the queue of work gets, the *slower* the query to pull the next job! The more Delayed:::Job workers are running the bigger problem it becomes.

Considering alternatives (such as [Resque](http://resquework.org) we decided that we'd like to retain database as the "source of truth". We also would still like to use Delayed::Job logic for handling failed jobs, managing locking etc. All we need is a more suitable queue-server. This is where TomQueue comes in.

Great, how do I use it?
-----------------------

Ok, first you need an RabbitMQ server [installed](https://www.rabbitmq.com/download.html) and running. It also helps to have [Management Plugin](https://www.rabbitmq.com/management.html) enables. It'll enable RabbitMQ web interface at http://localhost:15672

Once you have this, open your projects `Gemfile` and add the entry:

    gem 'tom_queue'

Then, the next step is to add the generic TomQueue configuration - we stuff this into a Rails initializer:

``` ruby
require 'tom_queue/delayed_job'

TomQueue::DelayedJob.priority_map[1] = TomQueue::BULK_PRIORITY
TomQueue::DelayedJob.priority_map[2] = TomQueue::LOW_PRIORITY
TomQueue::DelayedJob.priority_map[4] = TomQueue::NORMAL_PRIORITY
TomQueue::DelayedJob.priority_map[3] = TomQueue::HIGH_PRIORITY

# Make sure internal exceptions in TomQueue make it to Hoptoad!
TomQueue.exception_reporter = ErrorService
TomQueue.logger = Rails.logger
```

The priority map maps Delayed Job's numerical priority values to discrete priority levels, of BULK, LOW, NORMAL and HIGH, since we can't support arbitrary priorities. Any un-mapped values are presumed to be NORMAL. See below for further discussion on how job-priority works.

The `logger` is a bog-standard `Logger` object that, when set, receives warnings and errors from the TomQueue internals, useful for figuring out what is going on and when things go wrong. The `exception_reporter`, if set, should respond to `notify(exception)` and will receive any exceptions caught during the job lifecycle. If this isn't set, exceptions will just be logged.

Now you need to configure TomQueue in your rails environments and wire in the AMQP broker configuration for them. In, for example, `config/environments/production.rb` add the lines:

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

TomQueue::DelayedJob.apply_hook!
```

Replacing `AMQP_CONFIG` with the necessary Bunny configuration for your environment. The `default_prefix` is prefixed onto all AMQP exchanges and queues created by tom-queue, which can be a handy name-space. If you omit the `apply_hook!` call, DelayedJob behaviour will not be changed, a handy back-out path if things don't quite go to plan :)

Ok, so what happens now?
------------------------

Hopefully, DelayedJob should work as-is, but notifications for job events should be pushed via the AMQP broker, relieving the database server of the queue responsibility. It's worth pointing out that the "true" job state still resides in the DB, messages via the broker purely instruct the worker to consider a particular job.

It does add a couple of methods to the `DelayedJob` class and instances, which allow you to re-populate the AMQP broker with any jobs that reside in the DB. This is good if your broker drops offline for some reason, and misses some notifications.

```ruby
job = Delayed::Job.first
job.tomqueue_publish
```

This will send a notification for a given job via the broker.

```ruby
Delayed::Job.tomqueue_republish
```

Will send a message for *all* jobs in the DB, useful to fill a fresh AMQP broker if it's missing messages or you have, for example, failed-over to a new broker.

So, how does this thing work?
-----------------------------

When we call `apply_hook!` in initializer it modifies Delayed::Job config so that it uses `TomQueue::DelayedJob::Job` class as a backend. This class defines an `after_save` hook for when the job is saved to the database. After job is persisted it gets published to the [RabbitMQ exchange](http://rubybunny.info/articles/exchanges.html). TomQueue uses [Bunny](http://rubybunny.info) gem for interacting with RabbitMQ broker.

After the job was scheduled it ends up in two places: the database and RabbitMQ queue. There're 5 possible queues:

- bulk priority;
- low priority;
- normal priority;
- high priority;
- deferred queue (more on that later);

You can specify what priority should the job have.

While code in `TomQueue::DelayedJob::Job#tomqueue_publish` runs within the app, Delayed::Job workers run repeatedly run `TomQueue::DelayedJob::Job#reserve` method. This method implements the main process of acquiring a job from the RabbitMQ queue.

In a nutshell it checks if there's a job available in all 4 priority queues (from high to bulk). If there's a job to run, it gets a message from the queue, gets job if from the message and then **retrieves the job from the DB** by id.

If there're no jobs, worker waits until one comes.

### Deferred jobs

Some jobs are have to be run at some point in the future. To separate the jobs that should be run immediately from the "deferred" jobs TomQueue has a separate deferred queue and a **separate process** to manage these jobs.

When the job is published to the queue `TomQueue::QueueManager` decides whether it should be published to one of the priority queues or to the deferred queue.

Note: It gets confusing sometimes, so it's important to remember that RabbitMQ messages don't get published to the queue. They get published to the **exchange** and then they're **routed** to the queue. E.g. TomQueue uses one exchange per all 4 priority queues.

If job's `run_at` attribute is set in the future it ends up in the deferred queue.

There's a special process that is started separately from all DJ workers (but at the same time) that only listens to the deferred queue. It reads all the messages that come to the queue and holds them in memory in a sorted by `run_at` queue.

If you look at the deferred queue in the web interface when this "deferred process" is running you'll noticed that messages in that queue are ["Unacked"](https://www.rabbitmq.com/reliability.html). It means that consumer (deferred process) received a message but didn't send an acknowledgment for it. In the semantics of the deferred process it means that job is waiting for the time to run in deferred process's memory. We do it this way in case deferred process dies before dispatching all deferred jobs. In that case all the unacknowledged messages just get re-queued to the deferred queue. `TomQueue::DeferredWorkManager` class is responsible for managing deferred jobs and runs in a separate process.

What about when I'm developing?
-------------------------------

Since Delayed Job itself hasn't really changed all that much, you can still use good old vanilla `delayed_job_active_record` and, for the most part, it should behave the same as with TomQueue, albeit less scalable with bigger queue sizes. Just omit the call to `TomQueue::DelayedJob.apply_hook!` in your development environment.

You can also, of course, run a development AMQP broker and wire it up as in production to try it all out.

Cool. Is it safe to use?
------------------------

Sure! We use it in production at FreeAgent pushing hundreds of thousands of jobs a day. That said, you do so at your own risk, and I'd advise understanding how it behaves before relying on it!

Do let us know if you find any bugs or improve it (or just manage to get it to work!!) open an issue or pull-request here or alternatively ping me a mail at thomas -at- freeagent -dot- com 
