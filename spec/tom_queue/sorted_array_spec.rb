require "spec_helper"

describe Range, 'tomqueue_binary_search' do

  it "should return nil for an empty range" do
    (0...0).tomqueue_binary_search.should be_nil
  end

  describe "for a single item range" do
    let(:range) { 5...6 }

    it "should yield the index" do
      range.tomqueue_binary_search do |index|
        @index = index
      end
      @index.should == 5
    end

    it "should return 0 if the yield returned -1" do
      range.tomqueue_binary_search { |index| -1 }.should == 5
    end

    it "should return 1 if the yield returned +1" do
      range.tomqueue_binary_search { |index| +1 }.should == 6
    end

    it "should return 0 if the yield returned 0" do
      range.tomqueue_binary_search { |index| 0 }.should == 5
    end
  end

  describe "for two item range" do
    let(:range) { 7..8 }

    it "should yield the lower number" do
      range.tomqueue_binary_search do |index|
        @index = index
        0
      end
      @index.should == 7
    end

    it "should return the lower number if the block returns -1" do
      range.tomqueue_binary_search { |i| -1 }.should == 7
    end
    it "should return the lower number if the block returns 0" do
      range.tomqueue_binary_search { |i| 0 }.should == 7
    end

    it "should yield the second number if the block returns +1" do
      range.tomqueue_binary_search do |i|
        if i == 7
          1
        elsif i == 8
          @yielded = true
          0
        end
      end
      @yielded.should be_truthy
    end
  end

  describe "for a three item range" do
    let(:range) { 7..9 }

    it "should yield the mid-point" do
      range.tomqueue_binary_search do |index|
        @index = index
        0
      end
      @index.should == 8
    end

    it "should return the mid-point if the block returns 0" do
      range.tomqueue_binary_search { |index| 0 }.should == 8
    end

    it "should recurse to the right on +1" do
      @yielded = []
      range.tomqueue_binary_search { |index| @yielded << index; 1 }.should == 10
      @yielded.should == [8,9]
    end

    it "should recurse to the left on -1" do
      @yielded = []
      range.tomqueue_binary_search { |index| @yielded << index; -1 }.should == 7
      @yielded.should == [8,7]
    end

  end

  describe "acceptance 1" do
    let(:range) { 0...100 }
    let(:value) { 43 }

    before do
      @yielded = []
      @result = range.tomqueue_binary_search { |i| @yielded << i; value <=> i }
    end

    it "should get the correct result" do
      @result.should == value
    end

    it "should yield the correct values" do
      @yielded.should == [49, 24, 36, 42, 45, 43]
    end
  end

  describe "acceptance 2" do
    let(:range) { 0..3 }
    let(:value) { 3 }

    before do
      @yielded = []
      @result = range.tomqueue_binary_search { |i| @yielded << i; value <=> i }
    end

    it "should get the correct result" do
      @result.should == value
    end

    it "should yield the correct values" do
      @yielded.should == [1,2,3]
    end
  end


end



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
