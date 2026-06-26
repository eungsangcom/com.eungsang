const fs = require('fs');
const path = require('path');

const baseDir = path.resolve(__dirname, '..');
const docPaths = [
  path.join(baseDir, 'eungsang', '_docs', 'CLAUDE.md'),
];

function checkFile(filePath) {
  if (!fs.existsSync(filePath)) {
    return `Missing file: ${path.relative(baseDir, filePath)}`;
  }
  const content = fs.readFileSync(filePath, 'utf8');
  if (!content.includes('hub-spoke') && !content.includes('Star Topology')) {
    return `Missing hub-spoke guidance in ${path.relative(baseDir, filePath)}`;
  }
  return null;
}

function main() {
  const errors = docPaths.map(checkFile).filter(Boolean);
  if (errors.length > 0) {
    console.error(errors.join('\n'));
    process.exit(1);
  }
  console.log('validate-harness: OK');
}

main();
