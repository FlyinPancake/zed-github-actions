// Sits between Zed and the language server and works around differences
// between Zed and VS Code, the editor the server is written for:
// - It answers the server's custom `actions/readFile` request, which Zed doesn't
//   implement. The server uses it to read local reusable workflows
//   (`uses: ./...` and `uses: $/...`).
// - It clips completion edits that reach past the end of the line. On a blank
//   line the server completes a placeholder key it inserted into its own copy of
//   the document, so the edit covers text that doesn't exist. VS Code clips such
//   edits; Zed drops the completion.
//
// Usage: node proxy.mjs <server> [args...]
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const server = spawn(process.execPath, process.argv.slice(2), {
	stdio: ["pipe", "pipe", "inherit"],
});
server.on("exit", (code, signal) => process.exit(code ?? (signal ? 1 : 0)));
server.on("error", (error) => {
	console.error(`Failed to start language server: ${error.message}`);
	process.exit(1);
});

// The server uses full document sync, so every change carries the whole text.
const documents = new Map();
// Id -> completion request, to clip the edits in the response.
const requests = new Map();

// Zed -> server: forward each message whole, so responses written by the
// proxy are never spliced into the middle of one.
readMessages(process.stdin, (frame, body) => {
	const { id, method, params } = JSON.parse(body);
	if (method === "textDocument/didOpen") {
		documents.set(params.textDocument.uri, params.textDocument.text);
	} else if (method === "textDocument/didChange") {
		const text = params.contentChanges.at(-1)?.text;
		if (text !== undefined) documents.set(params.textDocument.uri, text);
	} else if (method === "textDocument/didClose") {
		documents.delete(params.textDocument.uri);
	} else if (method === "textDocument/completion") {
		requests.set(id, { method, uri: params.textDocument.uri });
	}
	server.stdin.write(frame);
});
process.stdin.on("end", () => server.stdin.end());

// Server -> Zed: answer `actions/readFile`, clip completion edits, forward
// everything else.
readMessages(server.stdout, (frame, body) => {
	const message = JSON.parse(body);
	const request = message.method === undefined && requests.get(message.id);
	if (message.method === "actions/readFile" && message.id !== undefined) {
		respond(message.id, message.params?.path);
	} else if (request) {
		requests.delete(message.id);
		clipCompletionEdits(message.result, documents.get(request.uri));
		send(process.stdout, message);
	} else {
		process.stdout.write(frame);
	}
});

function clipCompletionEdits(result, text) {
	const lines = text?.split(/\r?\n/);
	const items = Array.isArray(result) ? result : result?.items;
	if (!lines || !items) return;
	for (const { textEdit } of items) {
		for (const range of [textEdit?.range, textEdit?.insert, textEdit?.replace]) {
			for (const position of range ? [range.start, range.end] : []) {
				const length = lines[position.line]?.length;
				if (length !== undefined) position.character = Math.min(position.character, length);
			}
		}
	}
}

async function respond(id, uri) {
	let result = null;
	try {
		// vscode-uri encodes the drive colon on Windows (`file:///c%3A/...`).
		const url = new URL(uri.replace(/^file:\/\/\/([a-z])%3A/i, "file:///$1:"));
		if (url.protocol === "file:") {
			result = await readFile(fileURLToPath(url), "utf8");
		}
	} catch {
		// The server reports a missing file (`null`) as "Unable to find reusable workflow".
	}
	send(server.stdin, { jsonrpc: "2.0", id, result });
}

function send(stream, message) {
	const body = JSON.stringify(message);
	stream.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
}

/** Splits an LSP byte stream into messages and calls `onMessage(frame, body)` for each. */
function readMessages(stream, onMessage) {
	let buffer = Buffer.alloc(0);
	stream.on("data", (chunk) => {
		buffer = Buffer.concat([buffer, chunk]);
		for (;;) {
			const headerEnd = buffer.indexOf("\r\n\r\n");
			if (headerEnd === -1) return;
			const length = Number(/content-length: *(\d+)/i.exec(buffer.subarray(0, headerEnd))?.[1]);
			const end = headerEnd + 4 + length;
			if (Number.isNaN(length) || buffer.length < end) return;
			onMessage(buffer.subarray(0, end), buffer.subarray(headerEnd + 4, end).toString("utf8"));
			buffer = buffer.subarray(end);
		}
	});
}
