module vibe.templ.diet_compiler;

import vibe.templ.diet, vibe.templ.parsertools;
import std.algorithm, std.array, std.file, std.path, std.stdio;

void compileDiet(string path, string[] paths, string outDir)
{
	import std.string : tr;

	auto name = path.baseName;
	auto outPath = buildPath(outDir, name.stripExtension.tr(".-", "__").setExtension(".d"));
	if (outPath.exists && outPath.timeLastModified > path.timeLastModified)
		return;
	writefln("Precompiling diet template '%s'...", name);
	TemplateBlock[] files;

	void readFile(string path, string name)
	{
		auto lines = removeEmptyLines(path.readText(), name);
		TemplateBlock ret;
		ret.name = name;
		ret.lines = lines;
		ret.indentStyle = detectIndentStyle(lines);

		files ~= ret;
		foreach (dep; extractDependencies(lines))
		{
			if (files.canFind!((f, d) => f.name == d)(dep)) continue;
			auto res = paths.find!((p, d) => p.baseName == d)(dep);
			import std.exception : enforce;
			enforce(res.length, "Can't find dependency '"~dep~"' required by '"~name~"'.");
			readFile(res[0], res[0].baseName);
		}
	}

	readFile(path, name);

	auto compiler = DietCompiler!()(&files[0], &files, new BlockStore);
	enum base_indent = 0;
	std.file.write(outPath, `
module `~outPath.baseName.stripExtension~`;

import vibe.core.stream : OutputStream;
import vibe.templ.diet : _toStringS;
import vibe.templ.utils : localAliases;
import vibe.textfilter.html : filterHTMLEscape;
import std.typetuple : TypeTuple;
void render(ALIASES...)(OutputStream stream__)
{
	// some imports to make available by default inside templates
	import vibe.http.common;
	import vibe.stream.wrapper;
	import vibe.utils.string;

	mixin(localAliases!(0, ALIASES));

	static if (is(typeof(diet_translate__))) alias TRANSLATE = TypeTuple!(diet_translate__);
	else alias TRANSLATE = TypeTuple!();

	auto output__ = StreamOutputRange(stream__);

`~compiler.buildWriter(base_indent)~
`
}
`);
}


void main()
{
	import std.process, std.range, std.stdio : writeln;

	auto paths = appender!(string[])();
	foreach (arg; environment["STRING_IMPORT_PATHS"].splitter())
	{
		dirEntries(arg, SpanMode.shallow)
			.filter!(de => de.isFile && de.name.extension == ".dt")
			.map!(de => de.name)
			.copy(paths);
	}

	auto outDir = environment["IMPORT_PATHS"].splitter
		.find!(a => a.baseName == "precompiled_diet").front;
	if (!outDir.exists)
		mkdir(outDir);
	foreach (path; paths.data)
		compileDiet(path, paths.data, outDir);
}
