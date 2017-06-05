# Configure DelayedJob
Delayed::Worker.backend = :active_record
Delayed::Worker.sleep_delay = 5
Delayed::Worker.max_attempts = 5
Delayed::Worker.destroy_failed_jobs = false
Delayed::Worker.max_run_time = 20.minutes
Delayed::Worker.logger = Rails.logger
