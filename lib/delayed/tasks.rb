# Maintain compatibility with anyone calling `require "delayed/tasks"`

$stderr.puts " !! require 'delayed/tasks' called"
load("tom_queue/tasks")
