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
      current_length = length

      pos = if current_length == 0 || element < first
        0
      elsif element > last
        current_length
      else
        (0..current_length).bsearch { |idx| element < self[idx] }
      end

      insert(pos, element)
    end
  end
end
