#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

let data = {};
try {
  const input = fs.readFileSync(0, 'utf8');
  data = JSON.parse(input);
} catch (e) {}

const state = data.agent_state || 'idle';
const workspaceDir = (data.workspace && data.workspace.current_dir) || data.cwd || '';

let workspace = 'unknown';
if (workspaceDir) {
  const match = workspaceDir.match(/^\/google\/src\/cloud\/[^/]+\/([^/]+)/);
  if (match) {
    workspace = match[1];
  } else {
    workspace = path.basename(workspaceDir.replace(/\/+$/, '')) || 'unknown';
  }
}

const emojis = {
  initializing: '🚀',
  idle: '😴',
  thinking: '🤔',
  working: '🏃',
  tool_use: '🛠️',
  running: '🏃',
  processing: '⚙️',
};
const emoji = emojis[state.toLowerCase()] || '🤖';

console.log(`${emoji} ${state} | ${workspace}`);
