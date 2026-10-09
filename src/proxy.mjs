// Sits between Zed and the language server and answers the server's custom
// `actions/readFile` request, which Zed doesn't implement. The server uses it
// to read local reusable workflows (`uses: ./...` and `uses: $/...`).
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

// Zed -> server: forward each message whole, so responses written by the
// proxy are never spliced into the middle of one.
readMessages(process.stdin, (frame) => server.stdin.write(frame));
process.stdin.on("end", () => server.stdin.end());

// Server -> Zed: answer `actions/readFile`, forward everything else.
readMessages(server.stdout, (frame, body) => {
	const message = JSON.parse(body);
	if (message.method === "actions/readFile" && message.id !== undefined) {
		respond(message.id, message.params?.path);
	} else {
		process.stdout.write(frame);
	}
});

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
	const body = JSON.stringify({ jsonrpc: "2.0", id, result });
	server.stdin.write(`Content-Length: ${Buffer.byteLength(body)}\r\n\r\n${body}`);
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
