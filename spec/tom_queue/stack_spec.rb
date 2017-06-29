require "tom_queue/helper"

describe TomQueue::Stack do
  class Square < TomQueue::Stack::Layer
    def call(a, b)
      chain.call(a ** 2, b.merge(foo: "bar"))
    end
  end

  class Add < TomQueue::Stack::Layer
    def call(a, b)
      value = config[:value] || 1
      chain.call(a + value, b)
    end
  end

  class TestStack < TomQueue::Stack
    use Add, value: 2
    use Square
    use Add, value: 1
    insert Add, value: 3

    # result = ((x + 3 + 2) ** 2) + 1
  end

  specify "should compose layers and call them all in the correct order" do
    value, options = TestStack.call(1, {})
    expect(value).to eq(37)
    expect(options).to eq({foo: "bar"})
  end

  describe TomQueue::Stack::Layer do
    it "should be callable" do
      value, options = Square.new.call(2, {})
      expect(value).to eq(4)
      expect(options).to eq({foo: "bar"})
    end

    it "should be chainable" do
      layer = Square.new(Add.new())
      expect(layer).to be_a(Square)
      expect(layer.chain).to be_a(Add)
      expect(layer.chain.chain).to eq(TomQueue::Stack::TERMINATOR)
    end

    it "should be configurable" do
      layer = Square.new(nil, foo: "bar")
      expect(layer.config[:foo]).to eq("bar")
    end

    it "should be appendable" do
      layer = Square.new(Add.new)
      expect(layer.chain.chain).to eq(TomQueue::Stack::TERMINATOR)
      layer.append(Square, foo: "bar")
      expect(layer.chain.chain).to be_a(Square)
      expect(layer.chain.chain.config[:foo]).to eq("bar")
    end
  end
end
