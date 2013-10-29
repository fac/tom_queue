tom_queue
=========

TomQueue hooks onto delayed_job_active_record[https://github.com/collectiveidea/delayed_job_active_record] to move the work-load queue out of the database onto a more suitable queueing server (RabbitMQ).

Why?
----

At FreeAgent, we have always used Delayed Job to manage asynchronous work and find it still fits our needs well, not only in getting code running in production but also in its handling of failed jobs as well as having our entire engineering team understand how it works. It's a core part of our workflow and infrastructure and we're happy with it.

That said, when it is backed by MySQL, as we have it, we've found that it performs particularly poorly with larger queue sizes. In fact, the larger the queue of work gets, the *slower* it gets! To cut a long story short, databases make really poor queues.

Rather than move our "Source of Truth" for jobs and their state out of the database (and re-wire our jobs to use something like Resque, etc.) I've opted to fix the problem by replacing the queue of work to do with a more suitable server, namely AMQP / RabbitMQ. This is where this library comes in.

Great, how do I use it?
-----------------------

Ok, first you need an AMQP broker, we recommend and use RabbitMQ. Once you have this, open your projects `Gemfile` and add the entry:

    gem 'tom_queue'

Then, the next step is to configure where your AMQP broker is and install the hook. Create a rails initializer with some configuration:

    require 'tom_queue/delayed_job'
    TomQueue::DelayedJob.priority_map[1] = TomQueue::BULK_PRIORITY
    TomQueue::DelayedJob.priority_map[2] = TomQueue::LOW_PRIORITY
    TomQueue::DelayedJob.priority_map[4] = TomQueue::NORMAL_PRIORITY
    TomQueue::DelayedJob.priority_map[3] = TomQueue::HIGH_PRIORITY

    # Make sure internal exceptions in TomQueue make it to Hoptoad!
    TomQueue.exception_reporter = ErrorService
    TomQueue.logger = Rails.logger

The priority map relates Delayed Job's numerical priority values to discrete priority levels, of BULK, LOW, NORMAL and HIGH. Any un-mapped priorities are presumed to be NORMAL. See below for further discussion on how job-priority works.

The `logger` is a bog-standard `Logger` object that emits warnings and errors from the TomQueue internals, useful for figuring out what is going on. The `exception_reporter`, if set, should respond to `notify(exception)` and any caught exceptions will be forwarded to this object. If this isn't set, exceptions will just be logged.

Now you need to pick which environments should use TomQueue, and wire in the AMQP broker configuration for them. In, for example, `config/environments/production.rb` add the lines:

    TomQueue.bunny = Bunny.new( ... )
    TomQueue.bunny.start
    TomQueue.default_prefix = "tomqueue-production"

    TomQueue::DelayedJob.apply_hook!

Replacing the `...` with the necessary Bunny configuration for your environment. The `default_prefix` is prefixed onto all AMQP exchanges and queues created by tom-queue, which can be a handy name-space. If you omit the `apply_hook!` call, DelayedJob behaviour will not be changed, a handy back-out path if things don't quite go to plan :)

Ok, so what happens now?
------------------------

Hopefully, DelayedJob should work as-is, but notifications for job events should be pushed via the AMQP broker, relieving the database server of the queue responsibility. It's worth pointing out that the "true" job state still resides in the DB, messages via the broker purely instruct the worker to run particular jobs.

It does add a couple of methods to the `DelayedJob` class and instances, which allow you to re-populate the AMQP broker with any jobs that reside in the DB. This is good if your broker drops offline for some reason, and misses some notifications.

    job = Delayed::Job.first
    job.tomqueue_publish

This will send a notification for a given job via the broker.

    Delayed::Job.tomqueue_republish

Will send a message for *all* jobs in the DB, useful to fill a fresh AMQP broker if it's missing messages or you have, for example, failed-over to a new broker.

So, how does this thing work?
-----------------------------

Magic dust. Seriously.

What about when I'm developing?
-------------------------------

Since Delayed Job itself hasn't really changed all that much, you can still use good old vanilla `delayed_job_active_record` and, for the most part, it should behave the same as with TomQueue, albeit less scalable with bigger queue sizes. Just omit the call to `TomQueue::DelayedJob.apply_hook!` in your development environment.

You can also, of course, run a development AMQP broker and wire it up as in production to try it all out.

Cool. Is it safe to use?
------------------------

Sure! We use it in production at FreeAgent pushing hundreds of thousands of jobs a day. That said, you do so at your own risk, and I'd advise understanding how it behaves before relying on it!

Do let us know if you find any bugs or improve it (or just manage to get it to work!!) open an issue or pull-request here or alternatively ping me a mail at thomas -at- freeagent -dot- com 




