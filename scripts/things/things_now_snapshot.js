// A successful complete snapshot is required before declaring a batch finished.
function run(argv) {
    var t = Application('com.culturedcode.ThingsMac');
    if (!t.running()) throw Error('Things is not running');
    var tag = t.tags.byId(argv[0]);
    if (!tag.exists()) throw Error('Now tag unavailable');
    var trash = t.lists.byId('TMTrashListSource');
    function snapshot(item) {
        var projectId = '', projectName = '';
        try { var p = item.project(); projectId = p.id(); projectName = p.name(); } catch (_) {}
        return {id:item.id(), name:item.name(), status:String(item.status()), project_id:projectId, project_name:projectName};
    }
    var tasks = tag.toDos().filter(function(x) {
        return !t.projects.byId(x.id()).exists() && !trash.toDos.byId(x.id()).exists() && String(x.status()) === 'open';
    }).map(snapshot);
    var current = tasks.map(function(x) { return x.id; });
    var departed = {};
    JSON.parse(argv[1]).forEach(function(id) {
        if (current.indexOf(id) >= 0) return;
        var x = t.toDos.byId(id);
        if (!x.exists() || trash.toDos.byId(id).exists()) departed[id] = 'deleted';
        else {
            var status = String(x.status());
            departed[id] = status === 'open' ? 'removed' : status;
        }
    });
    return JSON.stringify({tasks:tasks, departed:departed});
}
