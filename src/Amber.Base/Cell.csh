namespace Amber.Base;

/// A mutable value that copies share (C#: a field of a class that several owners see change). CShift structs are copied
/// on assignment; a Cell is a handle to one shared value, like List<T> is a handle to shared elements.
///
///     var count = Cell<int>.Of(0);
///     var copy = count;
///     copy.Set(5);            // count.Get() is 5 too
struct Cell<T>
{
	T[] _value;

	static Cell<T> Of(T value)
	{
		var cell = Cell<T> { _value = new T[1] };

		cell._value[0] = value;

		return cell;
	}

	T Get()
	{
		return _value[0];
	}

	void Set(T value)
	{
		_value[0] = value;
	}
}
