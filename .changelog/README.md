# Changelog

`unreleased.md` collects the release notes for the next release. Add a line in the same commit that makes the change. The release skill translates the file, turns it into the GitHub release notes, and empties it again.

## What goes in

A change that a user can see or feel. Not dependency bumps, refactorings, tests, CI or lint fixes.

Leave out a fix for a bug that never reached a release. If the branch broke it and the branch fixed it, no user ever saw it. If a change is reverted before the release, delete its line.

Move a change to Maintenance when nobody can see it at work. Examples are hygiene in the generated files and small corrections to the interface. Collect those in one line, or leave them out.

## How to write an entry

Start with a bold text of eight words at most. It says what changed. The details follow in normal text.

The bold text has to work on its own. A reader who scans the bold texts alone has to know what happened. A topic label like "The Settings screen" fails this test, because it names a place and not a change. "Settings asks one question per screen" passes it.

Write the rest in plain English:

- One idea per sentence, 25 words at most.
- Simple tenses and active voice.
- No semicolons and no em dashes.
- Use can, will and must. Do not use should, may, might or could.
- Explain a technical term at its first use, in a few words. Example: "A broker is the server that passes MQTT messages between devices."
- Use the words of the user interface.

The list is an extract of the `simple-english` skill. Call that skill when a whole section needs a rewrite. A single line does not need it.

Under Fixes, write what works now. Do not describe the old bug.

Add "(#466)" when an issue or a discussion drove the change, and only where that issue is the subject of the entry. An issue or a discussion of the main repository needs the full name, as in "(solectrus/solectrus#5828)", because a bare number points at this repository.

## One change, one entry

Merge entries that describe the same change from two sides. Watch for these cases:

- The same change under "Before the update" and under "New features".
- A new gate and the fix behind it, in two different sections.
- Several entries about one screen, one generated file or one import.

A reader counts entries. Six entries about the import read as six problems.

## How to order

"Before the update" comes first. It holds what an installation that already runs has to act on, an address that changes or a setting that goes. It stays empty otherwise.

Then the most important entry first. Group a long section with "###" subheadings by topic. A section under about six entries does not need them.

Keep every section, an empty one included.

## Copy rules

The copy rules of the user interface apply: no Docker vocabulary, no second-person address, no em dashes.
