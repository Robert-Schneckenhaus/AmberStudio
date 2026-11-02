// Sizes of the fixed parts of the chunk layout (spec sections 3 and 6).

namespace Amber.Script.Common.ChunkLayout;

/// Group table header: u16 groupCount, u16 reserved.
const int GroupTableHeaderSize = 4;

/// Group record header: [mode:8][ruleCount:8], totalWords.
const int GroupHeaderSize = 4;

/// Rule record header: condWords, actionWords, next, reserved.
const int RuleHeaderSize = 8;

/// Binding table header: u16 count, u16 reserved.
const int BindingTableHeaderSize = 4;

/// Binding entry: 8 words.
const int BindingSize = 16;
