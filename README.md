# zed-github-actions
[![Zed Extension][zed-extension-badge]][zed-extension-url]
[![License][license-badge]][license-url]

[zed-extension-badge]: https://img.shields.io/badge/Zed%20Extension-%230951CF?style=flat-square&logo=zedindustries&logoColor=white&labelColor=black
[zed-extension-url]: https://zed.dev/extensions/github-actions
[license-badge]: https://img.shields.io/badge/License-Apache%202.0-blue?style=flat-square&labelColor=black&color=blue
[license-url]: #license

GitHub Actions LSP support for Zed. As this repository uses code based on some official Zed extensions (e.g [Svelte](https://github.com/zed-extensions/svelte) and [Astro](https://github.com/zed-extensions/astro)), this repository is under the same license as those.
To develop this extension, see the [Developing Extensions](https://zed.dev/docs/extensions/developing-extensions) section of the Zed docs.

- Tree-sitter: [zed-industries/tree-sitter-yaml](https://github.com/zed-industries/tree-sitter-yaml)
- Language Server: [actions/languageservices](https://github.com/actions/languageservices), installed from the [`@actions/languageserver`](https://www.npmjs.com/package/@actions/languageserver) NPM package

> [!NOTE]
> The language server reads local reusable workflows (`uses: ./...` and `uses: $/...`) by sending the editor a custom `actions/readFile` request, which Zed doesn't support. The extension starts the server through a small Node script ([`src/proxy.mjs`](src/proxy.mjs)) that answers this request from disk and passes every other message through unchanged.

## Configuring
### Filetype settings
This extension by default does not have any file associations built-in, as Zed doesn't support glob patterns at the extension-level to recognize a language within a specific directory. Instead, you can edit your Zed settings file (`settings.json`) with:

```jsonc
{
	// ...
	"file_types": {
		"GitHub Actions": [
			".github/workflows/*.yml",
			".github/workflows/*.yaml"
		]
	}
}
```

This extension avoids conflicting with the built-in YAML support for Zed by following how other Zed extensions for specific YAML files resolve this issue, including the [Ansible](https://github.com/kartikvashistha/zed-ansible) extension and [Docker Compose](https://github.com/eth0net/zed-docker-compose) extension.

### LSP settings
You can configure the LSP settings in Zed with:

```jsonc
{
	// ...
	"lsp": {
		"gh-actions-language-server": {
			"initialization_options": {
				// ...
			}
		}
	}
}
```

#### Default settings
The extension sets these `initialization_options` by default. Any key you set in your Zed settings replaces the default for that key.
```jsonc
{
	// See "Session token" below for where this comes from
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
```

#### Session token
The extension looks for a GitHub token in this order:
1. `sessionToken` in your Zed settings
2. `GITHUB_TOKEN`, then `GH_TOKEN`, in your shell environment
3. `gh auth token`, if the [GitHub CLI](https://cli.github.com) is installed and logged in

If you already use the GitHub CLI, run `gh auth login` once and restart the language server. Nothing else needs to be configured. The token belongs to the CLI's active account for github.com and has the CLI's scopes.

Without a token, the language server still validates workflows, but it can't fetch anything from github.com. Completion of action inputs (the keys under `with:`) needs a token and a `repos` entry for the worktree.

The server documents that it needs the `repo` and `workflow` scopes, which also cover the secrets, variables and environments of private repositories. To complete inputs of public actions, read access to public repositories is enough. If you don't use the GitHub CLI, create a PAT (Personal Access Token):
- [Classic PATs](https://github.com/settings/tokens/new): a token with no scopes can read public repositories. Add `repo` and `workflow` for everything else.
- [Fine-grained PATs](https://github.com/settings/personal-access-tokens/new), which can either be given access to:
  - "Public repositories"
  - "All repositories"/"Only select repositories" with repository permissions to `Workflows`

#### Repository settings
The extension runs `git remote get-url origin` in the worktree root to fill in `repos`. It can't do that when git isn't installed or when `origin` isn't on github.com, and it assumes the repository isn't owned by an organization. In those cases, set `repos` yourself. Zed replaces the whole array, so include every field:

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
						// Lets the server fetch organization secrets and variables
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

`workspaceUri` must match the start of the document URIs Zed sends, so use the path Zed shows for the project, without resolving symlinks.

## License
Licensed under Apache License, Version 2.0 ([`LICENSE-APACHE`](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>).

### Contribution
Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in the work by you, as defined in the Apache-2.0 license, shall be licensed as above, without any additional terms or conditions.
