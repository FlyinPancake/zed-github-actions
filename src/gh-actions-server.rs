use std::collections::HashSet;
use zed_extension_api::*;

const PACKAGE_NAME: &str = "@actions/languageserver";
const BINARY_NAME: &str = "actions-languageserver";

struct GitHubActionsExtension {
	installed: HashSet<String>,
}

impl GitHubActionsExtension {
	fn binary_path() -> String {
		std::env::current_dir()
			.unwrap()
			.join("node_modules")
			.join(PACKAGE_NAME)
			.join(format!("bin/{BINARY_NAME}"))
			.to_string_lossy()
			.to_string()
	}

	fn install_package_if_needed(
		&mut self,
		id: &LanguageServerId,
		package_name: &str,
	) -> Result<()> {
		use LanguageServerInstallationStatus::*;
		let installed_version = npm_package_installed_version(package_name)?;

		// If package is already installed in this session, then we won't reinstall it
		if installed_version.is_some() && self.installed.contains(package_name) {
			return Ok(());
		}

		set_language_server_installation_status(id, &CheckingForUpdate);

		let latest_version = npm_package_latest_version(package_name)?;

		if installed_version.as_ref() != Some(&latest_version) {
			println!("Installing {package_name}@{latest_version}...");

			set_language_server_installation_status(id, &Downloading);

			if let Err(error) = npm_install_package(package_name, &latest_version) {
				// If installation failed, but we don't want to error but rather reuse existing version
				if installed_version.is_none() {
					Err(error)?;
				}
			}
		} else {
			println!("Found {package_name}@{latest_version} installed");
		}

		self.installed.insert(package_name.into());
		Ok(())
	}

	/// Finds a GitHub token in `GITHUB_TOKEN`, `GH_TOKEN`, or `gh auth token`, unless
	/// the user already set `sessionToken` in their settings.
	fn session_token(id: &LanguageServerId, worktree: &Worktree) -> Option<String> {
		let user_token = settings::LspSettings::for_worktree(id.as_ref(), worktree)
			.ok()
			.and_then(|settings| settings.initialization_options)
			.and_then(|options| options.get("sessionToken")?.as_str().map(str::to_owned));
		if user_token.is_some_and(|token| !token.is_empty()) {
			return None;
		}

		let env = worktree.shell_env();
		let env_token = ["GITHUB_TOKEN", "GH_TOKEN"].iter().find_map(|name| {
			env.iter()
				.find(|(key, value)| key == name && !value.is_empty())
				.map(|(_, value)| value.clone())
		});
		if env_token.is_some() {
			return env_token;
		}

		// Pass the shell environment so `gh` is found on the user's `PATH` and reads
		// its config from the usual place.
		let output = process::Command::new("gh")
			.args(["auth", "token"])
			.envs(env)
			.output()
			.ok()?;
		let token = String::from_utf8(output.stdout).ok()?.trim().to_string();
		(output.status == Some(0) && !token.is_empty()).then_some(token)
	}

	/// Builds the `RepositoryContext` the server needs to look up action inputs,
	/// runner labels, etc. Returns `None` if the origin isn't a GitHub repository.
	fn repo_context(worktree: &Worktree) -> Option<serde_json::Value> {
		// Fails if `.git` is a file (git worktree or submodule), which is fine:
		// users can set `repos` themselves in that case.
		let git_config = worktree.read_text_file(".git/config").ok()?;
		let (owner, name) = parse_github_remote(&origin_url(&git_config)?)?;

		Some(serde_json::json!({
			"id": 0,
			"owner": owner,
			"name": name,
			"organizationOwned": false,
			"workspaceUri": file_uri(&worktree.root_path()),
		}))
	}
}

/// Returns the URL of the `origin` remote from the contents of a `.git/config` file.
fn origin_url(git_config: &str) -> Option<String> {
	let mut in_origin = false;
	for line in git_config.lines().map(str::trim) {
		if line.starts_with('[') {
			in_origin = line == r#"[remote "origin"]"#;
		} else if in_origin
			&& let Some((key, value)) = line.split_once('=')
			&& key.trim() == "url"
		{
			return Some(value.trim().to_string());
		}
	}
	None
}

/// Parses `owner` and `name` from a GitHub remote URL in any of these forms:
/// `https://github.com/o/n`, `git@github.com:o/n`, `ssh://git@github.com/o/n`,
/// each with an optional `.git` suffix.
fn parse_github_remote(url: &str) -> Option<(String, String)> {
	let path = [
		"https://github.com/",
		"ssh://git@github.com/",
		"git@github.com:",
	]
	.iter()
	.find_map(|prefix| url.strip_prefix(prefix))?;
	let path = path.trim_end_matches('/');
	let (owner, name) = path.strip_suffix(".git").unwrap_or(path).split_once('/')?;
	if owner.is_empty() || name.is_empty() || name.contains('/') {
		return None;
	}
	Some((owner.to_string(), name.to_string()))
}

/// Converts a directory path to a `file://` URI with a trailing slash, encoded the
/// same way Zed encodes document URIs, so the server's `startsWith` check matches.
fn file_uri(path: &str) -> String {
	let mut uri = String::from("file://");
	// Windows paths (`C:\foo`) become `file:///C:/foo`.
	let path = if path.starts_with('/') {
		path.to_string()
	} else {
		uri.push('/');
		path.replace('\\', "/")
	};
	for byte in path.trim_end_matches('/').bytes() {
		match byte {
			b'/' => uri.push('/'),
			b'\0'..=b' '
			| b'"'
			| b'#'
			| b'%'
			| b'<'
			| b'>'
			| b'?'
			| b'['
			| b'\\'
			| b']'
			| b'`'
			| b'{'
			| b'}'
			| 0x7f.. => uri.push_str(&format!("%{byte:02X}")),
			_ => uri.push(byte as char),
		}
	}
	uri.push('/');
	uri
}

impl Extension for GitHubActionsExtension {
	fn new() -> Self {
		Self {
			installed: HashSet::new(),
		}
	}

	fn language_server_command(
		&mut self,
		language_server_id: &LanguageServerId,
		_worktree: &Worktree,
	) -> Result<Command> {
		self.install_package_if_needed(language_server_id, PACKAGE_NAME)?;

		Ok(Command {
			command: node_binary_path()?,
			args: vec![Self::binary_path(), "--stdio".to_string()],
			env: Default::default(),
		})
	}

	fn language_server_initialization_options(
		&mut self,
		language_server_id: &LanguageServerId,
		worktree: &Worktree,
	) -> Result<Option<serde_json::Value>> {
		// Zed merges `lsp.gh-actions-language-server.initialization_options` from the
		// user's settings over these, so any key set there takes precedence.
		let mut options = serde_json::json!({
			"sessionToken": Self::session_token(language_server_id, worktree).unwrap_or_default()
		});
		if let Some(repo) = Self::repo_context(worktree) {
			options["repos"] = serde_json::json!([repo]);
		}
		Ok(Some(options))
	}
}

register_extension!(GitHubActionsExtension);

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn parses_origin_url() {
		let config = "[core]\n\tbare = false\n[remote \"upstream\"]\n\turl = https://github.com/a/b\n[remote \"origin\"]\n\turl = git@github.com:o/n.git\n\tfetch = +refs/heads/*:refs/remotes/origin/*\n";
		assert_eq!(
			origin_url(config).as_deref(),
			Some("git@github.com:o/n.git")
		);
		assert_eq!(origin_url("[core]\n\tbare = false\n"), None);
	}

	#[test]
	fn parses_github_remotes() {
		let expected = Some(("o".to_string(), "n".to_string()));
		for url in [
			"https://github.com/o/n",
			"https://github.com/o/n.git",
			"git@github.com:o/n",
			"git@github.com:o/n.git",
			"ssh://git@github.com/o/n",
			"ssh://git@github.com/o/n.git",
		] {
			assert_eq!(parse_github_remote(url), expected, "{url}");
		}
		assert_eq!(parse_github_remote("https://gitlab.com/o/n.git"), None);
		assert_eq!(parse_github_remote("https://github.com/o"), None);
	}

	#[test]
	fn encodes_file_uri() {
		assert_eq!(file_uri("/var/home/me/repo"), "file:///var/home/me/repo/");
		assert_eq!(file_uri("/a b/[x]#ű"), "file:///a%20b/%5Bx%5D%23%C5%B1/");
		assert_eq!(file_uri(r"C:\Users\me"), "file:///C:/Users/me/");
	}
}
