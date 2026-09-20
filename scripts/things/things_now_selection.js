function run(argv) {
    var t = Application('com.culturedcode.ThingsMac');
    if (!t.frontmost() || t.windows[0].name() !== argv[0]) throw Error('Things window changed');
    var selected = t.selectedToDos();
    if (!selected.length) throw Error('Select tasks to add to Now');
    var tasks = selected.map(function(item) {
        var projectId = '', projectName = '';
        try { var p = item.project(); projectId = p.id(); projectName = p.name(); } catch (_) {}
        return {id:item.id(), name:item.name(), project_id:projectId, project_name:projectName};
    });
    return JSON.stringify({tasks:tasks});
}
