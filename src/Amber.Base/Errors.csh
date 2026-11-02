// CShift has no exceptions: functions that can fail return Error<T>. The C# implementation told the kinds of failures apart
// by exception type (InvalidChunkException, InvalidPackException ...); here the kind is the code of the error:
//
//     return error("The chunk is truncated.", (int)ErrorKind.InvalidChunk);
//     if (result is Error<Foo> failure && failure.Code == (int)ErrorKind.InvalidPack) ...

namespace Amber.Base;

enum ErrorKind : int32
{
	None = 0,
	/// A script or screen chunk does not follow the chunk layout (InvalidChunkException).
	InvalidChunk = 1,
	/// The pack file is broken (InvalidPackException).
	InvalidPack = 2,
	/// The checksum of a pack chunk does not match (PackChecksumException, a kind of InvalidPack).
	PackChecksum = 3,
	/// The pack does not contain the requested chunk (PackChunkNotFoundException, a kind of InvalidPack).
	PackChunkNotFound = 4,
	/// The pack asks for natives the game does not implement (MissingNativeException, a kind of InvalidPack).
	MissingNative = 5,
	/// Content (YAML, tables, screens) is wrong (InvalidDataException).
	InvalidData = 6,
	/// A savegame is damaged or from an unknown version (InvalidSaveException).
	InvalidSave = 7,
	/// A scenario file is wrong or cannot be run (ScenarioException).
	Scenario = 8,
	/// A syntax error of AmberScript (SyntaxException, E100).
	Syntax = 9,
	/// A wrong argument of a function (ArgumentException).
	Argument = 10,
	/// An operation that is not possible in the current state (InvalidOperationException).
	InvalidOperation = 11,
	/// A file could not be read or written.
	Io = 12
}

/// True for the error codes of a broken pack (InvalidPackException and its subclasses).
bool IsInvalidPackError(int code)
{
	return code == (int)ErrorKind.InvalidPack || code == (int)ErrorKind.PackChecksum || code == (int)ErrorKind.PackChunkNotFound
		|| code == (int)ErrorKind.MissingNative;
}
