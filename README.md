# zed-github-actions

<!--[![Zed Extension][zed-extension-badge]][zed-extension-url]-->
[![License][license-badge]][license-url]

<!--[zed-extension-badge]: https://img.shields.io/badge/Zed%20Extension-%230951CF?style=flat-square&logo=zedindustries&logoColor=white&labelColor=black-->
<!--[zed-extension-url]: https://zed.dev/extensions/github-actions-->
[license-badge]: https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square&labelColor=black&color=blue
[license-url]: #license

> [!NOTE]
> This extension is a fork of [neoncitylights/zed-github-actions](https://github.com/neoncitylights/zed-github-actions).
> It runs the current official language server, makes completion, links and local reusable workflows work in Zed, and
> adds syntax highlighting for expressions and `run:` scripts.

GitHub Actions support for Zed, for workflow files in `.github/workflows/`.

## Features

- Diagnostics from the official [GitHub Actions language server](https://github.com/actions/languageservices), such as
  unknown keys, invalid values, and missing required inputs.
- Completion of keys and values, and of contexts and functions inside `${{ ... }}`.
- Completion of action inputs under `with:`, for example `node-version` for `actions/setup-node`. This needs a
  [GitHub token](#github-token).
- Completion of the inputs of reusable workflows, both remote (`owner/repo/.github/workflows/x.yml@ref`) and local
  (`./.github/workflows/x.yml` or `$/.github/workflows/x.yml`).
- Documentation on hover.
- Ctrl+click on `uses:` opens actions and remote workflows on GitHub, and local workflows in Zed.
- An experimental quick fix that adds the missing required inputs of an action step. Turn it on with
  `"experimentalFeatures": { "missingInputsQuickfix": true }` in the [settings](#settings).
- Readable descriptions of `cron` schedules as inlay hints. Zed shows inlay hints only when
  `"inlay_hints": { "enabled": true }` is set in your Zed settings.
- Syntax highlighting of `${{ ... }}` expressions and of `if:` conditions.
- Syntax highlighting of `run:` scripts as bash, PowerShell or Python. The extension uses the step's `shell:`, then the
  job's `defaults.run.shell`, then the runner's default, which is PowerShell on Windows runners and bash elsewhere. It
  doesn't read the workflow's `defaults.run.shell`, and it assumes runners from a matrix aren't Windows. PowerShell
  highlighting needs the [PowerShell extension](https://zed.dev/extensions/powershell).

## Usage

The extension isn't published, so install it as a dev extension. Clone this repository, run `zed: install dev extension`
from the command palette, and pick the clone. Zed builds the extension with Rust, so you need a Rust toolchain installed
through `rustup`.

### File types

Zed extensions can't match files by directory, so the extension has no file associations of its own. This keeps it from
taking over every YAML file. Map your workflow files to it in your Zed settings (`settings.json`):

```jsonc
{
	"file_types": {
		"GitHub Actions": [
			"**/.github/workflows/*.yml",
			"**/.github/workflows/*.yaml"
		]
	}
}
```

The [Ansible](https://github.com/kartikvashistha/zed-ansible) and
[Docker Compose](https://github.com/eth0net/zed-docker-compose) extensions use the same approach.

### GitHub token

Without a token, the language server validates workflows and completes keys, but it can't fetch anything from GitHub.
Action inputs, runner labels, environments, secrets and variables come from the GitHub API.

The extension looks for a token in this order:

1. `sessionToken` in the language server settings (see [Settings](#settings))
2. `GITHUB_TOKEN`, then `GH_TOKEN`, in your shell environment
3. `gh auth token`, if the [GitHub CLI](https://cli.github.com) is installed

If you use the GitHub CLI, run `gh auth login` once and restart the language server. The extension then uses the token
of the CLI's active github.com account.

To complete the inputs of public actions, the token only needs read access to public repositories. The server asks for
the `repo` and `workflow` scopes, which add the secrets, variables and environments of private repositories. If you
don't use the GitHub CLI, create a personal access token:

- A [classic token](https://github.com/settings/tokens/new) with no scopes can read public repositories. Add `repo` and
  `workflow` for private repositories.
- A [fine-grained token](https://github.com/settings/personal-access-tokens/new) needs access to "Public repositories",
  or to the repositories you work on with the `Workflows` repository permission.

## Settings

The language server takes its settings from `lsp.gh-actions-language-server.initialization_options`. The extension sends
these defaults, and each key you set replaces the default for that key:

```jsonc
{
	"lsp": {
		"gh-actions-language-server": {
			"initialization_options": {
				// See "GitHub token" above
				"sessionToken": "",
				// Only sent if the worktree's `origin` remote is on github.com
				"repos": [
					{
						"id": 0,
						"owner": "<owner>",
						"name": "<repo>",
						"organizationOwned": false,
						"workspaceUri": "file:///path/to/worktree/"
					}
				]
			}
		}
	}
}
```

### Repository

The extension runs `git remote get-url origin` in the worktree root to fill in `repos`. Local reusable workflows and
action input completion need this entry. If git isn't installed or `origin` isn't on github.com, the extension sends no
`repos`, and you can set it yourself. Set it too if the repository belongs to an organization, so the server also
fetches the organization's secrets and variables. Zed replaces the whole array, so include every field:

```jsonc
{
	"lsp": {
		"gh-actions-language-server": {
			"initialization_options": {
				"repos": [
					{
						"id": 0,
						"owner": "my-org",
						"name": "my-repo",
						"organizationOwned": true,
						// The worktree root as a `file://` URI, with a trailing slash
						"workspaceUri": "file:///home/me/projects/my-repo/"
					}
				]
			}
		}
	}
}
```

`workspaceUri` has to match the start of the file URIs that Zed sends to the server. Use the project path that Zed
shows, without resolving symlinks.

## How it works

- The language server is the [`@actions/languageserver`](https://www.npmjs.com/package/@actions/languageserver) npm
  package from [actions/languageservices](https://github.com/actions/languageservices). The extension installs the
  latest version.
- The server is written for VS Code. The extension starts it through a Node script, [`src/proxy.mjs`](src/proxy.mjs),
  that changes three things and passes every other message through:
  - The server reads local reusable workflows with a custom `actions/readFile` request, which Zed doesn't support. The
    script reads the file from disk and answers the request.
  - On a blank line, the server returns completion edits that reach past the end of the line, and Zed drops them. The
    script shortens the edits to the end of the line.
  - The server's links to `uses: $/...` workflows point into a `$` directory that doesn't exist. The script removes that
    directory from the link.
- YAML parsing uses [zed-industries/tree-sitter-yaml](https://github.com/zed-industries/tree-sitter-yaml).
- Expressions are parsed by [FlyinPancake/tree-sitter-gh-actions-expressions][expressions-fork], a fork of
  [Hdoc1509/tree-sitter-gh-actions-expressions][expressions-upstream]. The fork parses single-character names,
  properties of function results such as `fromJSON(...).name`, and operators in function arguments.

[expressions-fork]: https://github.com/FlyinPancake/tree-sitter-gh-actions-expressions
[expressions-upstream]: https://github.com/Hdoc1509/tree-sitter-gh-actions-expressions

## Development

See [Developing Extensions](https://zed.dev/docs/extensions/developing-extensions) in the Zed docs.

## License

This repository uses code from official Zed extensions, such as [Svelte](https://github.com/zed-extensions/svelte) and
[Astro](https://github.com/zed-extensions/astro), and uses the same license.

Licensed under Apache License, Version 2.0 ([`LICENSE`](LICENSE) or <http://www.apache.org/licenses/LICENSE-2.0>).

### Contribution

Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as
defined in the Apache-2.0 license, shall be licensed as above, without any additional terms or conditions.
