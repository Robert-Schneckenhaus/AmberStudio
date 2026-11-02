// The seeded random numbers of .NET (System.Random with a seed: Knuth's subtractive generator, the "Net5CompatSeedImpl"
// of the runtime). The map generators use it so that they write the same maps as the C# reference implementation.

namespace Amber.Player.Tools;

using System;

const int RandomBig = 2147483647;
const int RandomSeed = 161803398;

/// A seeded random number generator; copies share the state.
struct DotNetRandom
{
	/// 1..55: the table of the generator, 56: the index of the next value, 57: the second index.
	int[] _state;

	static DotNetRandom Create(int seed)
	{
		var state = new int[58];
		int subtraction = seed == -2147483648 ? RandomBig : (seed < 0 ? -seed : seed);
		int mj = RandomSeed - subtraction;
		int mk = 1;
		int ii = 0;

		state[55] = mj;

		for (var i = 1; i < 55; i += 1)
		{
			ii += 21;

			if (ii >= 55)
				ii -= 55;

			state[ii] = mk;
			mk = mj - mk;

			if (mk < 0)
				mk += RandomBig;

			mj = state[ii];
		}

		for (var k = 1; k < 5; k += 1)
		{
			for (var i = 1; i < 56; i += 1)
			{
				int n = i + 30;

				if (n >= 55)
					n -= 55;

				state[i] -= state[1 + n];

				if (state[i] < 0)
					state[i] += RandomBig;
			}
		}

		state[56] = 0;
		state[57] = 21;

		return DotNetRandom { _state = state };
	}

	int InternalSample()
	{
		int next = _state[56] + 1;
		int nextP = _state[57] + 1;

		if (next >= 56)
			next = 1;

		if (nextP >= 56)
			nextP = 1;

		int result = _state[next] - _state[nextP];

		if (result == RandomBig)
			result -= 1;

		if (result < 0)
			result += RandomBig;

		_state[next] = result;
		_state[56] = next;
		_state[57] = nextP;

		return result;
	}

	/// A number in [0, 1).
	double Sample()
	{
		return (double)InternalSample() * (1.0 / (double)RandomBig);
	}

	/// A number in [0, maxValue).
	int Next(int maxValue)
	{
		return (int)(Sample() * (double)maxValue);
	}

	/// A number in [minValue, maxValue).
	int Next(int minValue, int maxValue)
	{
		int64 range = (int64)maxValue - (int64)minValue;

		return (int)(Sample() * (double)range) + minValue;
	}
}
