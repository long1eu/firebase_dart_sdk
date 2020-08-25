const xcode = require('xcode');
const pbxFile = require('xcode/lib/pbxFile');
const fs = require('fs');

const path = process.argv[2];
const servicePath = process.argv[3];
if (!path || !servicePath) {
    throw new Error('No path provided');
}

const project = xcode.project(path);
project.parseSync();

const group = 'Runner';
const file = new pbxFile(servicePath, {});
if (project.hasFile(file.path)) {
    return false;
}

file.uuid = project.generateUuid();
file.fileRef = project.generateUuid();

project.addToPbxBuildFileSection(file);
project.addToPbxFileReferenceSection(file);
project.addToPbxResourcesBuildPhase(file);
project.addToPbxGroup(file, project.findPBXGroupKey({path: group}));

fs.writeFileSync(path, project.writeSync());