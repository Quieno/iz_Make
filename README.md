# iz_Make

*The one Makefile to rule them all.*

> **Context.** 42 School requires a hand-written Makefile — no wildcards, no shell globs, every source file listed explicitly. A rogue `.c` sitting in `src/` should not silently end up in your binary just because it ended up on the wrong place. I understand the reasoning. That did not make repeating it any less tedious.

---

## Table of Contents

- [**Origin**](#origin)
- [**Design Evolution**](#design-evolution)
- [**Limitations**](#limitations)
- [**Usage & Examples**](#usage--examples)
- [**AI Usage**](#ai-usage)
- [**Roadmap**](#roadmap)

---
---

# Origin

I was told more than once that a Makefile is something you write carefully once and then reuse with minimal changes across projects. That is probably true if all your projects have the same shape. Mine did not. Every new one needed something different, a different source structure was not the end of it, sometimes it's a new dependency, two programs instead of one, or one program with two builds that could not share a rule name. Each time, "minimal changes" meant rewriting something load-bearing, and I really do not like fixing Makefiles.

So I developed a habit I am not particularly proud of, but while actually working on a project, I would just use wildcards, get everything building without thinking about it, and only go back and write the explicit list by hand right before submitting for evaluation. I understood why the rule existed. Writing it out by hand forces you to know your own project and be mindfull about the file structure. I just found the act itself unreasonably boring for something that a computer could trivially do for me.

The side effect was worse. Changing a project's structure, even moving a file, splitting a module, reorganizing a folder, it all meant touching the Makefile. And I would rather leave a messy pile of loosely related files sitting in one directory than open that file again. I left some genuinely ugly project trees standing purely out of Makefile avoidance.

At some point I got tired of the whole cycle. The rule says the *build* step cannot use wildcards generate the file list on the fly. It says nothing about making a script to in one step: scan the project once and write a literal, hardcoded list that happens to satisfy the rule to the letter. One scan, on demand, stored in plain sight as a diff-able block in the Makefile itself. Build reads the block, never touches the filesystem. A rogue file does nothing unless someone runs the scan again.

Once that separation existed, almost everything else followed from one question: *what actually changes between projects?* Mostly, which files belong to which output, and how many outputs there are. The rest: compiling, linking, cleaning, is the same every time. The whole system ended up being built around answering that one question as automatically as possible, for as many project shapes as I could think of, so that the number of lines I have to change before being ready to build something new is as close to zero as I can get it.

---
---

# Design Evolution

**Shaping the tool to be as lazy as possible** originally this idea was just a standalone script to get the structure, to later copy and paste it on the makefile, but i would still need to solve many details to get an actually usable Makefile at the end, maybe i could do the script generate the full Makefile... or i could figure out how to make makefile make all the changes to itself.

**Suffixes and output names are separate** because some projects had two builds of the same codebase with different names and features — `make foo` produced `foo_bin`, `make bar` produced `bar_extra`. Making the directory name and the output name independent meant that worked without any special casing. Any subdirectory of `src/` whose name matches a declared suffix is exclusive to that output. Everything else is compiled once and shared by all of them.

**BLOCK came from needing one output to be opt-in instead of automatic.** Some projects had a "default" version and a second build with `bonus` features that should only be built when explicitly requested. BLOCK makes `make build` skip certain outputs while keeping `make <suffix>` working for all of them. A little later I added a second use for the same key: blocked names that aren't declared outputs get excluded from the directory scan entirely, which is what lets you leave experimental, outdated, or in-progress folders sitting in the project without them showing up in the build.

**Modules came from a dependency problem.** A library's `.a` file doesn't exist at the start of a project — it has to be built. If this Makefile could recognize another Makefile in the dependency tree as something that uses the same conventions, it could build that dependency first, know exactly what file it produces and where, and link it automatically. Drop a library's folder into `inc/` and it gets found, built, and linked, in this project and in the next one, with no edits anywhere. The structure acts with pseudo-recursion, each module is responsible for its own dependencies, and the root project only ever knows about its direct children.

**Third-party support was the last real gap.** Modules built with this Makefile work cleanly. Libraries that use their own build system entirely do not, and excluding them entirely would make the whole thing too limited to be genuinely useful. The escape hatch is a small hand-written section outside the generated block: each third-party dependency declares where its Makefile lives, what artifact it produces, and an id used to store its link flags. The same suffix-matching logic decides whether it is shared or exclusive. `clean` makes a best-effort attempt and moves on if the foreign Makefile doesn't have that target. `fclean` at least removes the artifact directly, since that path is always known regardless of whether the foreign project cleans anything.

---
---

# Limitations

**Whitespace in file or directory names is dangerous** and not something I have fully tested. Everything relies on space-separated shell lists internally.

**The structure is rigid about exclusivity.** A source file or dependency is either exclusive to exactly one suffix, or common to all of them. There is no way to say "shared by `foo` and `bar` but not `baz`." The most important limitation in the whole system, and one I don't have a clean solution for yet. There are ways to bend the existing structure to get this behaviour, but they feel like workarounds more than a proper baked in feature.

**One `TYPE` per project.** Everything in a single Makefile builds either programs or libraries, not a mix of both, this would be an easy change, but is not yet relevant to me.

---
---

# Usage & Examples

## Rules

```sh
make sync     # scan src/ and inc/, rewrite the generated block
make          # build every non-blocked output (relay modules and third-party first)
make <suffix> # build one specific output, even if it's blocked
make clean    # remove object files recursively (third-party: best-effort)
make fclean   # remove object files and outputs (third-party: artifacts always removed)
make re       # fclean + build
```

`sync` only needs to run again when the *structure* changes: new directories, new modules, or a changed `PROGRAMS`/`BLOCK`. Modiffing existing files doesn't need it. Editing a header doesn't need `re` either: every `.c` file gets a `.d` file at compile time that tracks which headers it includes, so only the files that actually need to recompile will.

## Configuration

| Key | What it does |
|---|---|
| `TYPE` | `program` (link with `cc`) or `library` (archive with `ar`) |
| `PROGRAMS` | `suffix:name` pairs, one per output |
| `BLOCK` | excluded from `make build` if a suffix; excluded from the scan entirely if not |
| `OUTDIR` | where outputs land, a directory name, or `root` to put them in the project root |
| `SRCDIR` / `INCDIR` / `OBJDIR` | source, header, and object directories, defaults `src` / `inc` / `obj` |
| `3RDDIR` | `sync` skips this directory name anywhere it appears; declare its contents in `THIRD_PARTY` |

## Examples

**A static library:**
```makefile
TYPE     = library
PROGRAMS = lib:foo
OUTDIR   = root
```
`make` produces `foo.a` in the project root.

---

**A program that depends on a library:**
```makefile
TYPE     = program
PROGRAMS = main:foo
OUTDIR   = bin
```
Drop the library's folder into `inc/`. `sync` finds its Makefile, reads what it produces, and adds it to the link step. Nothing else to configure.

---

**Two builds of the same codebase, one built by default:**
```makefile
PROGRAMS = foo:example bar:example_extra
BLOCK    = bar
```
`make` builds `example`. `make bar` builds `example_extra`. Files in `src/foo/` and `src/bar/` are exclusive to their respective outputs. Everything else is shared. `src/scratch/` and `src/old/` disappear from the scan entirely if added to `BLOCK`.

---

**Two programs that share most of their code:**
```makefile
PROGRAMS = foo:foo_bin bar:bar_bin
```
`src/foo/` and `src/bar/` hold what makes each program different. Everything else in `src/` is compiled once and linked into both.

---

**A dependency that uses its own build system:**
```makefile
3RDDIR      = 3rd
THIRD_PARTY = ext:inc/3rd/foo:libext.a
ext         = -lm
```
`inc/3rd/foo` holds a foreign project. `sync` never opens it. `relay-build` builds it with its own Makefile before anything else is compiled. Since the path ends in `foo` (a declared suffix) `libext.a` and `-lm` are linked exclusively into `foo_bin`. A third-party path that doesn't end in a suffix would be linked into everything.

---
---

# AI Usage

Every decision in this project, what the system should do, how exclusivity should be determined, what relay should and shouldn't know about, how third-party modules should be declared and classified, what `clean` and `fclean` should guarantee, came from me. What I don't have is fluency in bash or a complete mental model of how Make expands variables and evaluates recipes at parse time versus execution time. In practice that meant: I would describe a rule in plain language, sometimes as pseudocode, sometimes just explaining what the output should look like given a specific input, and AI would translate that into working shell and Make syntax. Most rounds were the same loop, describe the expected behavior, get an implementation, run it against a real test project, find where what Make actually does diverged from what either of us thought it would do, fix it. The spaces-before-tabs that Make silently refuses to treat as recipes. The `$(eval)` that expands a variable at the wrong moment. The sync block that duplicated itself on the second run. None of those were caught by reading, they were caught by the build failing, which turned out to be a perfectly good way to find out which parts of Make I only thought I understood.

---
---

# Roadmap

- [ ] `make run` — for programs, launch the built binary with configurable arguments; for projects with multiple programs, a small workflow that runs them together in the right order
- [ ] `make test` — for libraries, build a test suite against the library and run it, so any change can be verified with one command without manually compiling a test harness every time
- [ ] `flexibility` — any added feature that will let me build more types of projects, and therefore: allow me to last longer before needing to actually change a Makefile again.
