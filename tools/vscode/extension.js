// Loon VS Code Extension — LSP client
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

let client;

function activate(context) {
    const serverOptions = {
        command: 'python3',
        args: [context.asAbsolutePath('../lsp/loon-lsp.py')],
        transport: TransportKind.stdio
    };

    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'loon' }]
    };

    client = new LanguageClient('loon', 'Loon Language Server', serverOptions, clientOptions);
    client.start();
}

function deactivate() {
    if (client) return client.stop();
}

module.exports = { activate, deactivate };
