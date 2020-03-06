const xcode = require('xcode');

const path = process.argv[0];
if (!path) {
    throw new Error('No path provided');
}

const project = xcode.project(path);
project.parseSync();

project.addResourceFile();
console.log(project.writeSync());


