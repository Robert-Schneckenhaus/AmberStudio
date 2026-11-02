// Stable sorting with a comparison function (C#: OrderBy/ThenBy, List.Sort with a Comparison). CShift has no lambdas, so the
// comparison is a named function: Func<T, T, int> compare = CompareByName;

namespace Amber.Base;

using System;

/// Sorts the list in place, stable (equal elements keep their order), like LINQ's OrderBy.
void SortList<T>(List<T> list, Func<T, T, int> compare)
{
	int count = list.Count();

	if (count < 2)
		return;

	var items = list.ToArray();
	var sorted = SortArray(items, compare);

	for (var i = 0; i < count; i += 1)
		list.Set(i, sorted[i]);
}

/// A sorted copy of the array (stable merge sort).
T[] SortArray<T>(T[] items, Func<T, T, int> compare)
{
	int count = items.Length;
	var source = items.Clone();
	var target = new T[count];

	for (var width = 1; width < count; width *= 2)
	{
		for (var start = 0; start < count; start += 2 * width)
		{
			int middle = Math.Min(start + width, count);
			int end = Math.Min(start + 2 * width, count);
			int left = start;
			int right = middle;
			int index = start;

			while (left < middle && right < end)
			{
				if (compare(source[right], source[left]) < 0)
				{
					target[index] = source[right];
					right += 1;
				}
				else
				{
					target[index] = source[left];
					left += 1;
				}

				index += 1;
			}

			while (left < middle)
			{
				target[index] = source[left];
				left += 1;
				index += 1;
			}

			while (right < end)
			{
				target[index] = source[right];
				right += 1;
				index += 1;
			}
		}

		var swap = source;

		source = target;
		target = swap;
	}

	return source;
}

/// The ordinal comparison of two strings (C#: StringComparer.Ordinal, string.CompareOrdinal).
int CompareOrdinal(string a, string b)
{
	return a.CompareTo(b);
}

int CompareInt(int a, int b)
{
	return a < b ? -1 : (a > b ? 1 : 0);
}

/// The elements of a list as an array (an empty array for an empty list; List<T>.ToArray gives null for it).
T[] ArrayOf<T>(List<T> list)
{
	if (list.Count() == 0)
		return new T[0];

	return list.ToArray();
}
