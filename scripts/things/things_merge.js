function run(argv) {
    var t = Application('com.culturedcode.ThingsMac');
    var request = JSON.parse(argv[1]);
    var ids = request.ids;
    function verifySelection() {
        if (!t.frontmost() || t.windows[0].name() !== request.window) throw Error('窗口已改变，未合并');
        var selected = t.selectedToDos().map(function(x) { return x.id(); });
        if (JSON.stringify(selected) !== JSON.stringify(ids)) throw Error('选择已改变，未合并');
    }
    verifySelection();
    if (ids.length < 2 || ids.length !== Array.from(new Set(ids)).length) throw Error('请先选择至少两条任务');
    var items = ids.map(function(id) {
        var x = t.toDos.byId(id);
        if (!x.exists() || t.projects.byId(id).exists() || String(x.status()) !== 'open' || t.lists.byId('TMTrashListSource').toDos.byId(id).exists()) throw Error('仅合并未完成任务');
        return x;
    });
    var snapshots = items.map(function(x) { return JSON.parse(x._private_experimental_Json()); });
    if (argv[0] === 'snapshot') return JSON.stringify(snapshots);
    if (JSON.stringify(snapshots) !== JSON.stringify(request.snapshots)) throw Error('任务内容已改变，未合并');
    verifySelection();
    var target = items[0];
    target.name = request.name;
    target.notes = request.notes;
    target.tagNames = request.tags;
    if (target.name() !== request.name || target.notes() !== request.notes || target.tagNames().split(',').map(function(x) { return x.trim(); }).sort().join(',') !== request.tags.split(',').map(function(x) { return x.trim(); }).sort().join(',')) throw Error('内容写入验证失败；原任务尚未移入废纸篓');
    // Keep the first task's ID, project, dates and native checklist intact.
    for (var i=1; i<items.length; i++) {
        t.delete(items[i]);
        if (!t.lists.byId('TMTrashListSource').toDos.byId(ids[i]).exists()) throw Error('移入废纸篓失败，请查看备份');
    }
    t.show(target);
    return JSON.stringify({id:ids[0], merged:ids.slice(1)});
}
