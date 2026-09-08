Iterable {
	Done {} # todo; I don't like that it's a class

	collection: Array
	next (index: Int -> Any;
		if index >= collection.length()
			Done()
		else
			collection[index]
		end
	)
}
