const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const test = require('node:test');

const source = fs.readFileSync(path.join(__dirname, '../launcher/static/app.js'), 'utf8');
const functions = ['comfyUrl', 'jupyterUrl', 'updateServiceLinks'].map(name => {
  const match = source.match(new RegExp(`function ${name}\\([^]*?^}`, 'm'));
  assert.ok(match, `Missing ${name}`);
  return match[0];
}).join('\n');

function context(hostname, protocol='https:') {
  const value = {window: {location: {hostname, protocol}},
    elements: {serviceComfy: {}, serviceJupyter: {}}};
  vm.createContext(value);vm.runInContext(functions, value);return value;
}

test('RunPod header links use separate HTTPS proxy services', () => {
  const page=context('parity-test-3000.proxy.runpod.net');
  page.updateServiceLinks({});
  assert.equal(page.elements.serviceComfy.href, 'https://parity-test-8188.proxy.runpod.net');
  assert.equal(page.elements.serviceJupyter.href, 'https://parity-test-8888.proxy.runpod.net');
});

test('server-provided public URLs override browser fallbacks', () => {
  const page=context('parity-test-3000.proxy.runpod.net');
  page.updateServiceLinks({comfy_url:'https://comfy.example.test',jupyter_url:'https://lab.example.test'});
  assert.equal(page.elements.serviceComfy.href,'https://comfy.example.test');
  assert.equal(page.elements.serviceJupyter.href,'https://lab.example.test');
});

test('local fallback keeps RunPod Jupyter 8888, not Vast 8080', () => {
  const page=context('127.0.0.1','http:');page.updateServiceLinks({});
  assert.equal(page.elements.serviceComfy.href,'http://127.0.0.1:8188');
  assert.equal(page.elements.serviceJupyter.href,'http://127.0.0.1:8888');
});
