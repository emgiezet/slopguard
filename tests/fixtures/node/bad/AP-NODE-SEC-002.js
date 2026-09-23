const { exec, execSync } = require('child_process');

// ruleid: slopguard.node.exec-template-literal
function listFiles(directory) {
  exec(`ls -la ${directory}`, (err, stdout) => {
    console.log(stdout);
  });
}

// ruleid: slopguard.node.exec-template-literal
function convertImage(filename) {
  const output = execSync(`convert ${filename} -resize 800x output.jpg`);
  return output.toString();
}

// ruleid: slopguard.node.exec-template-literal
router.get('/scan', (req, res) => {
  const { host } = req.query;
  exec(`nmap -sV ${host}`, (err, stdout) => res.send(stdout));
});
