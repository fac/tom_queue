# Add a binary search method to Range.
#
# The search method has the same interface as Ruby 2.0's Range#bsearch method
# but a different name, so it should be easy to adopt 2.0's version.
#
class Range

  def tomqueue_binary_search
    return nil if min == nil

    low = min
    high = max

    while (low <= high)
      mid = (high + low) >> 1

      output = yield mid
      if output == 0
        return mid

      elsif output < 0
        if low == high || low+1 == high
          return low
        else
          high = mid - 1
        end
      elsif output > 0
        if mid == high
          return high + 1
        else
          low = mid + 1
        end
      end
    end
  end
end


module TomQueue

  # Internal A sorted array is one in which all the elements remain sorted
  #
  # On insertion, a binary search of the existing elements is carried out in order to find the
  # correct location for the new element.
  #
  # NOTE: This thread is /NOT/ thread safe, so it is up to the caller to ensure that concurrent
  # access is correctly synchronized.
  #
  # NOTE: You must also use the << method to add elements, otherwise this array isn't guaranteed to be
  # sorted!
  #
  class SortedArray < ::Array


    # Public: Add an element to the array.
    #
    # This will insert the element into the array in the correct place
    #
    # Returns self so this method can be chained
    def <<(element)
      pos = (0...self.length).tomqueue_binary_search do |index|
        element <=> self[index]
      end
      pos ||= 0 # this is for the empty array

      self.insert(pos, element)
    end
  end
end