// A readable text of a whole pack: header, table of contents and one section per chunk (spec section 9, task 3.5).

namespace Amber.Pack.PackDumper;

using System;
using Amber.Base;
using Amber.Screens;
using Amber.Script.Common;

string Dump(PackReader reader)
{
	var text = StringBuilder.Create();
	var header = reader.Header;
	var pack = PackContent.Of(reader);
	string profile = header.ProfileId == 0 ? " (desktop)" : (header.ProfileId == 1 ? " (amiga_a1200)" : "");

	text.AppendLine("Pack format " + header.FormatVersion + ", profile " + header.ProfileId + profile + ", flags 0x" + Hex((int)header.Flags, 4)
		+ (header.SymbolsIncluded() ? " (symbols)" : ""));
	text.AppendLine("Layout hash 0x" + Hex(header.LayoutHash, 8));
	text.AppendLine("Limits: threads " + header.MaxThreads + ", chain steps " + header.MaxChainSteps + ", screen depth " + header.MaxScreenDepth
		+ ", pending events " + header.MaxPendingEvents);
	text.AppendLine("Global state: " + header.GlobalFlags + " flags, " + header.GlobalVars + " vars, " + header.GlobalVars32 + " var32; natives: " + header.NativeCount);
	text.AppendLine();
	text.AppendLine("Table of contents (" + header.TocCount + " chunks, at offset " + header.TocOffset + "):");
	text.AppendLine("  type          id  offset   packed  unpacked  compression  crc16");

	foreach (var entry in reader.Entries)
	{
		text.AppendLine("  " + PadRight(TypeName(entry.Type), 12) + " " + PadLeft(entry.Id.ToString(), 5) + "  " + PadLeft(entry.Offset.ToString(), 6) + "  "
			+ PadLeft(entry.PackedSize.ToString(), 7) + "  " + PadLeft(entry.UnpackedSize.ToString(), 8) + "  " + PadRight(PackCompressionName(entry.Compression), 11)
			+ "  0x" + Hex((int)entry.Crc16, 4));
	}

	foreach (var entry in reader.Entries)
	{
		text.AppendLine();
		text.AppendLine("== " + TypeName(entry.Type) + " " + entry.Id + " ==");
		text.Append(Section(pack, entry));
	}

	return text.ToString();
}

string TypeName(PackChunkType type)
{
	if (EnumDefined(PackChunkTypeNames, (int)type))
		return PackChunkTypeName(type);

	return "0x" + Hex((int)type, 4);
}

string Section(PackContent pack, PackEntry entry)
{
	var text = StringBuilder.Create();
	var result = SectionText(pack, entry, text);

	if (result is error)
		text.AppendLine("  damaged: " + result.Message);

	return text.ToString();
}

/// Appends the section; on an error the text written so far stays (like the C# dumper, which catches the exception).
Error<void> SectionText(PackContent pack, PackEntry entry, StringBuilder text)
{
	var reader = pack.Reader;

	switch (entry.Type)
	{
		case PackChunkType.Scripts:
		{
			var bindings = new uint8[0];

			if (reader.Contains(PackChunkType.Bindings, 0))
				bindings = try reader.Get(PackChunkType.Bindings, 0);

			text.AppendLine(try ScriptDumper.Dump(try ScriptChunk.Create(try reader.Get(PackChunkType.Scripts, 0), bindings)));
			break;
		}
		case PackChunkType.Bindings:
			text.AppendLine("(dumped with the scripts)");
			break;
		case PackChunkType.Map:
		{
			var map = try pack.LoadMap((int)entry.Id);

			text.AppendLine("map '" + map.Name + "': " + map.Sizes.Flags + " flags, " + map.Sizes.Vars + " vars, " + map.Sizes.Vars32 + " var32, " + map.Entities.Length + " entities");

			foreach (var entity in map.Entities)
				text.AppendLine("  entity " + entity.Id + " '" + entity.Name + "' at (" + entity.X + ", " + entity.Y + ") kind " + entity.Kind);

			foreach (var routine in map.Routines)
			{
				text.AppendLine("  routine " + routine.Id + " '" + routine.Name + "' of entity " + routine.EntityId);

				foreach (var scheduled in routine.Entries)
				{
					var steps = new string[scheduled.Steps.Length];

					for (var i = 0; i < steps.Length; i += 1)
					{
						var step = scheduled.Steps[i];

						if (step.Kind == PackedRoutineStepKind.WalkTo)
							steps[i] = "walk_to " + step.Target;
						else if (step.Kind == PackedRoutineStepKind.Stay)
							steps[i] = "stay " + step.Ticks + " ticks";
						else
							steps[i] = "sleep";
					}

					text.AppendLine("    " + ZeroPad(scheduled.Minute / 60, 2) + ":" + ZeroPad(scheduled.Minute % 60, 2) + " " + string.Join("; ", steps));
				}
			}

			text.AppendLine(try ScriptDumper.Dump(map.Script));
			break;
		}
		case PackChunkType.Screen:
		{
			var screen = try pack.LoadScreen((int)entry.Id);
			var definition = screen.Definition;

			text.AppendLine("screen: flags " + ScreenFlagsText(definition.Flags) + ", region " + definition.Region.Text() + ", " + definition.ArgumentCount + " args, cursor " + definition.Cursor);
			text.AppendLine("  on_open " + Group(definition.OnOpen) + ", on_close " + Group(definition.OnClose) + ", on_resume " + Group(definition.OnResume));

			foreach (var rect in definition.Passthrough)
				text.AppendLine("  passthrough " + rect.Text());

			for (var i = 0; i < definition.Nodes.Length; i += 1)
			{
				var node = definition.Nodes[i];

				text.AppendLine("  node " + i + ": " + NodeTypeName(node.Type) + " id " + (node.Id == Wire.None ? "-" : node.Id.ToString()) + " parent "
					+ (node.Parent == Wire.None ? "-" : node.Parent.ToString()) + " at (" + node.X + ", " + node.Y + ") size " + node.Width + "x" + node.Height
					+ " layer " + node.Layer + " flags " + NodeFlagsText(node.Flags) + " text 0x" + Hex((int)node.Text, 4) + " click " + Group(node.OnClick));
			}

			for (var i = 0; i < definition.Literals.Length; i += 1)
				text.AppendLine("  literal " + i + ": \"" + definition.Literals[i] + "\"");

			text.AppendLine("state: " + screen.Sizes.Flags + " flags, " + screen.Sizes.Vars + " vars, " + screen.Sizes.Vars32 + " var32");
			text.AppendLine(try ScriptDumper.Dump(screen.Script));
			break;
		}
		case PackChunkType.Natives:
		{
			foreach (var native in try pack.Natives())
			{
				text.AppendLine("  " + PadLeft(native.Id.ToString(), 4) + " " + native.Name + (native.DataSource ? " (data source)" : "") + (native.Blocking ? " (blocking)" : "")
					+ " argc " + native.ArgumentCount);
			}

			break;
		}
		case PackChunkType.Layout:
			text.AppendLine((try pack.Layout()).Text());
			break;
		case PackChunkType.Symbols:
		{
			foreach (var symbol in try pack.Symbols())
				text.AppendLine("  " + SymbolKindName((SymbolKind)symbol.Kind) + " " + symbol.Id + " " + symbol.Name);

			break;
		}
		case PackChunkType.Text:
		{
			foreach (var pair in (try pack.Texts((int)entry.Id)).Entries())
				text.AppendLine("  " + pair.Key + ": " + pair.Value.Replace("\n", "\\n"));

			break;
		}
		case PackChunkType.Table:
			text.Append(try Table(pack, (int)entry.Id));
			break;
		default:
			text.AppendLine("  " + entry.UnpackedSize + " bytes");
			break;
	}

	return;
}

string Group(uint16 reference)
{
	if (reference == Wire.None)
		return "-";

	return Wire.IsLocalGroup(reference) ? "L" + Wire.GroupIndex(reference) : "G" + Wire.GroupIndex(reference);
}

Error<string> Table(PackContent pack, int id)
{
	var text = StringBuilder.Create();

	if (id == PackTableUiGraphics || id == PackTableCursors)
	{
		foreach (var name in try pack.Names(id))
			text.AppendLine("  " + name.Id + ": " + name.Name);
	}
	else
	{
		foreach (var pair in (try pack.Strings(id)).Entries())
			text.AppendLine("  " + pair.Key + ": " + pair.Value.Replace("\n", "\\n"));
	}

	return text.ToString();
}
