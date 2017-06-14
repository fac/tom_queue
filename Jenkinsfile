#!groovy
@Library("freeagent") _

freeagent("smartos") {
  stage("Install deps") {
    sh "bundle install"
  }

  stage("Test") {
    sh "bundle exec rspec"
  }
}
