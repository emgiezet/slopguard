const { execFile, spawn } = require('child_process');
const path = require('path');

// ok: slopguard.node.exec-template-literal
function listFiles(directory) {
  const safe = path.resolve(directory);
  execFile('ls', ['-la', safe], (err, stdout) => {
    console.log(stdout);
  });
}

// ok: slopguard.node.exec-template-literal
function convertImage(filename) {
  // arguments as array — no shell interpretation
  return new Promise((resolve, reject) => {
    execFile('convert', [filename, '-resize', '800x', 'output.jpg'], (err, stdout) => {
      if (err) reject(err);
      else resolve(stdout);
    });
  });
}
