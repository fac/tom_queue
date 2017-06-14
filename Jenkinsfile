#!groovy
@Library("freeagent") _

freeagent("smartos") {
  stage("Install deps") {
    sh "bundle install"
  }

  stage("Test") {
    sh "mysqladmin create delayed_job_test"
    sh "bundle exec rspec"
  }
}
