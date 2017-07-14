require "tom_queue/delayed_job"

# Configure DelayedJob
Delayed::Worker.backend = :active_record
Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_attempts = 5
Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_run_time = 20.minutes
Delayed::Worker.logger = Rails.logger

TomQueue.logger = Logger.new($stdout) if ENV['DEBUG']

TomQueue.config[:override_enqueue] = ENV["NEUTER_DJ"] == "true"

# JOB_PRIORITIES = [
#   LOWEST_PRIORITY   = 2,
#   LOW_PRIORITY      = 1,
#   NORMAL_PRIORITY   = 0,
#   HIGH_PRIORITY     = -1
# ]

# TomQueue::DelayedJob.priority_map[LOWEST_PRIORITY] = TomQueue::BULK_PRIORITY
# TomQueue::DelayedJob.priority_map[LOW_PRIORITY]    = TomQueue::LOW_PRIORITY
# TomQueue::DelayedJob.priority_map[NORMAL_PRIORITY] = TomQueue::NORMAL_PRIORITY
# TomQueue::DelayedJob.priority_map[HIGH_PRIORITY]   = TomQueue::HIGH_PRIORITY
