// Called by the explicit timer controls. Returns one immutable task snapshot.
function run(argv) {
    var things = Application('com.culturedcode.ThingsMac');
    if (argv.length && (!things.frontmost() || things.windows[0].name() !== argv[0])) throw Error('Things window changed');
    var tasks = things.selectedToDos();
    if (tasks.length !== 1) throw Error('Select exactly one Things task to start timing');
    var item = tasks[0];
    if (String(item.status()) !== "open" || things.projects.byId(item.id()).exists() || things.lists.byId("TMTrashListSource").toDos.byId(item.id()).exists()) throw Error("Select one open task to start timing");
    var projectName = '', projectId = '';
    try { var p = item.project(); projectName = p.name(); projectId = p.id(); } catch (_) {}
    return JSON.stringify({id:item.id(), name:item.name(), project_id:projectId, project_name:projectName});
}
