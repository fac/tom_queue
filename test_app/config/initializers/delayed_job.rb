require "tom_queue/delayed_job"

# Configure DelayedJob
Delayed::Worker.backend = :active_record
Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_attempts = 5
Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_run_time = 20.minutes
Delayed::Worker.logger = Rails.logger

# TomQueue::DelayedJob.priority_map[AppConstants::LOWEST_PRIORITY] = TomQueue::BULK_PRIORITY
# TomQueue::DelayedJob.priority_map[AppConstants::LOW_PRIORITY]    = TomQueue::LOW_PRIORITY
# TomQueue::DelayedJob.priority_map[AppConstants::NORMAL_PRIORITY] = TomQueue::NORMAL_PRIORITY
# TomQueue::DelayedJob.priority_map[AppConstants::HIGH_PRIORITY]   = TomQueue::HIGH_PRIORITY
