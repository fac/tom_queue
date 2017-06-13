require 'tom_queue/helper'

describe TomQueue::SortedArray do

  let(:array) { TomQueue::SortedArray.new }

  it "should insert in sorted order" do
    array << 4
    array << 5
    array << 2
    array << 1
    array << 3
    array.should == [1,2,3,4,5]
  end

  it "should work for all permutations of insertion" do
    numbers = [0,1,2,3,4,5,6]
    numbers.permutation.each do |permutation|
      array = TomQueue::SortedArray.new
      permutation.each do |i|
        array << i
      end
      array.should == numbers
    end
  end

  it "should return itself when inserting" do
    (array << 3).should == array
  end
end
