// Akvila VS Code Extension — LSP client
const vscode = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');

let client;

function activate(context) {
    const serverOptions = {
        command: 'python3',
        args: [context.asAbsolutePath('../lsp/akvila-lsp.py')],
        transport: TransportKind.stdio
    };

    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'akvila' }]
    };

    client = new LanguageClient('akvila', 'Akvila Language Server', serverOptions, clientOptions);
    client.start();
}

function deactivate() {
    if (client) return client.stop();
}

module.exports = { activate, deactivate };
