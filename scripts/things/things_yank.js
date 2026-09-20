// Read-only Things scripting; the keyboard watcher owns clipboard writes.
function formatTask(task) {
    var mark = task.status === 'completed' ? 'x' : task.status === 'canceled' ? '~' : ' ';
    var text = '- [' + mark + '] ' + task.name;
    if (task.notes) text += '\n' + task.notes.split(/\r\n|\r|\n/).map(function(line) { return '  ' + line; }).join('\n');
    return text;
}
function projectID(url) {
    var match = /[?&]id=([^&]+)/.exec(url);
    return match ? decodeURIComponent(match[1]) : null;
}
function run(argv) {
    var things = Application('com.culturedcode.ThingsMac');
    if (!things.frontmost() || things.windows[0].name() !== argv[1]) throw Error('Things window changed');
    var project = null;
    var items;
    if (argv[0] === 'project') {
        var id = projectID(things.currentListUrl());
        if (!id || !things.projects.byId(id).exists()) throw Error('Current list is not a project');
        project = things.projects.byId(id);
        items = project.toDos();
    } else {
        items = things.selectedToDos();
        if (!items.length) throw Error('No selected tasks');
    }
    var result = items.map(function(item) {
        return {name: item.name(), notes: item.notes() || '', status: String(item.status())};
    });
    var text = result.map(formatTask).join('\n\n');
    if (project) {
        text = '# ' + project.name() + '\n\n' + (project.notes() ? project.notes() + '\n\n' : '') + text;
    }
    return JSON.stringify({text: text, count: result.length, titles: result.map(function(item) { return item.name; })});
}
if (typeof module !== 'undefined') module.exports = {formatTask: formatTask, projectID: projectID};
