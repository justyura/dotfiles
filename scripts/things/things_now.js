function run(argv) {
    var t = Application('com.culturedcode.ThingsMac');
    var action = argv[0], bound = argv[1], tag;
    if (bound) {
        tag = t.tags.byId(bound);
        if (!tag.exists()) throw Error('Bound Now tag is unavailable');
    } else {
        var matches = t.tags.whose({name:'Now'})();
        if (matches.length > 1) throw Error('More than one Now tag');
        if (matches.length) tag = matches[0];
        else { tag = t.Tag({name:'Now'}); t.tags.push(tag); }
    }
    var added = [], already = [], restored = [], skipped = [], errors = [];
    if (action === 'enqueue' || action === 'migrate') {
        JSON.parse(argv[2]).forEach(function(task) {
            try {
                var item = t.toDos.byId(task.id);
                if (!item.exists() || t.projects.byId(task.id).exists() || t.lists.byId('TMTrashListSource').toDos.byId(task.id).exists()) {
                    skipped.push(task.id); return;
                }
                if (action === 'enqueue' && String(item.status()) !== 'open') { skipped.push(task.id); return; }
                if (action === 'migrate') {
                    if (item.project().id() !== argv[3]) { skipped.push(task.id); return; }
                    if (!task.project_id || !t.projects.byId(task.project_id).exists()) throw Error('Original project unavailable; task left in place');
                }
                if (item.tags().some(function(x) { return x.id() === tag.id(); })) already.push(task.id);
                else {
                    var names = item.tagNames();
                    item.tagNames = names ? names + ', ' + tag.name() : tag.name();
                    if (!item.tags().some(function(x) { return x.id() === tag.id(); })) throw Error('Tag did not persist');
                    added.push(task.id);
                }
                if (action === 'migrate') {
                    item.project = t.projects.byId(task.project_id);
                    if (item.project().id() !== task.project_id) throw Error('Restore did not persist');
                    restored.push(task.id);
                }
            } catch (error) { errors.push({id:task.id, message:String(error)}); }
        });
    }
    return JSON.stringify({tag_id:tag.id(), added:added, already:already, restored:restored, skipped:skipped, errors:errors});
}
