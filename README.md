# teanode-sources

Signed source type definitions for TeaNode.

A **source** is somewhere a person's TeaNode agent reads on their behalf: a chat server, a wiki, a tracker, a drive, a mailbox. A **source type** says how to read one kind of source with a command line tool the person already has on their own computer, signed in as them. The person installs a type once, adds a source of that type with its settings (which account, which spaces, which query), and chooses which of their attached computers runs it. `teanode computer` on that computer runs the type. No script is written or copied anywhere.

Folders of files and code are not a type here: TeaNode reads them with rules built into `teanode computer` (git awareness, whose work a checkout is, file readers), and shows them as the built-in "Files and code" type beside these.

**Status: draft.** The types under `sources/` describe what TeaNode is going to run; the runner does not exist yet, and `index.json` lists nothing until each type has been run against the tool it calls. The format below will change as that happens. See `docs/planning/installable-source-types-execplan.md` in the TeaNode repository.

## Layout

- `index.json`: the registry index TeaNode reads, one entry per published type, each with its version, the file's URL, its SHA-256 and an Ed25519 signature.
- `sources/<name>/source.md`: a type. YAML between `---` lines, then prose for people. A type is named for the service and the tool it calls, `<service>-<tool>` (`github-gh`, `gmail-gog`), or for the service alone when the tool is named after it (`confluence`), so two ways of reading one service can sit side by side.
- `keys/teanode-sources-ed25519-public.pem`: the key the signatures are checked against. TeaNode carries it built in; it is not the key that signs skills.
- `scripts/`, `Makefile`: hashing, signing and verifying the index, as in `teanode-skills`.

## The format

A type has a `name`, a `description`, `requires` (the tools it calls, checked before the first pass so a missing tool is reported as that), and `settings`: what a person fills in when adding a source, each with a `type`, an optional `default`, and a `pattern` the value has to match. A setting is passed to a command as a word of its own, never through a shell, and the pattern keeps a value from turning into a flag.

`containers` is how to list what the source holds: channels, repositories, spaces, folders. It is a list of listings, all of which run; their containers are joined by `name`. A listing is a `command` (a list of words), a `parse` block, a `paging` block, and the container's `name` and `fields`. A listing can run once `each` value of a setting that is a list, or once for each container of an earlier listing (`over`, naming that listing's `id`), or `walk` a tree, following the items it says are branches. A listing marked `only: parents` is listed to be walked into and not read itself, and `when` runs a listing only when its condition holds.

`records` is how to read one container: a list of readings, each a `command`, `parse`, `paging`, and a `record` block giving each field of the record (`id`, `kind`, `title`, `url`, `at`, `modifiedAt`, `author`, `channel`, `thread`, `private`, `text`, `version`) from the item. A reading can run once `each` value of a list written into it, `skip` items a condition picks out, and say that a command's not-found answer means `missing: empty` rather than a failure.

A listing can also be `fixed`: containers written into the type rather than listed, for a source that is one file (a mailbox).

`detail`, inside a reading, is a command run for an item whose `version` changed since the last pass, supplying its text. `attachments` is a command, or a list of them each with a `when`, that writes one file of an item to the path it is given as `{{output}}`, up to `maxBytes`. Both are cached on the computer by item and version, so an unchanged item costs nothing.

What a reading no longer lists is deleted when the pass completes, because that is how something removed from a service leaves the agent's memory too. A reading can say otherwise. `since` reads only what changed since the last complete pass over the container (`first` is where the first pass starts, `unchangedWhen` skips a container that says it has nothing new, and `window` reads in slices of time, oldest first, for a tool that cannot page); what such a reading does not see is kept. `unseen: keep` keeps it for a reading whose query is a moving window, so that what ages out of the window stays.

Templates: `{{settings.x}}`, `{{container.x}}`, `{{item.x}}`, `{{each}}`, `{{parent.x}}` for the container a listing runs `over`, `{{folder.x}}` for the folder a `walk` is in, `{{response.x}}` for the rest of the answer an item came in (with `[...]` to look a value up by another), `{{detail.text}}`, `{{output}}`, and `{{pass.since}}`, `{{pass.windowStart}}`, `{{pass.windowEnd}}`. Filters: `epoch-ms` (milliseconds as a time), `date`, `join ", "`, `replace "/" " "`, `urlencode`, `or <fallback>`, `empty`, and `flag "<when true>" "<when false>"`. A condition (`skip`, `when`, `branch`, `unchangedWhen`) compares with `==`, `!=`, `<=`, `in [...]` and `matches <pattern>`, joined with `&&`, `||` and `!`.

`parse` is `json` with `items` (a dotted path to the list; a path ending in `.*` takes the values of a map), `jsonl` (one object a line), `lines` (a regular expression whose named groups become the item's fields, with lines that do not match skipped), or `text` (the whole output, as `text`).

`paging` is `none`; `all` (the tool pages by itself, such as `gh api --paginate`); `token` with the answer's `field` holding the next page's token and the `flag` that passes it; or `limit` with a `flag` and a `size`, where a page that comes back full fails the pass, since it may have been cut.

The runner, not the type, keeps the rule every source depends on: a listing or reading that fails, answers something that does not parse, or may have been cut fails the whole pass and deletes nothing.

## Signing

As in `teanode-skills`:

    make hash      # update each entry's sha256 from sources/<name>/source.md
    make sign      # hash, then sign index.json with keys/teanode-sources-ed25519-private.pem
    make verify    # check every signature against the public key

The private key is never committed.
