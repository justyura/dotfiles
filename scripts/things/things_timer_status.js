// Authoritative task lifecycle check, including changes made outside this keyboard layer.
function run(argv) {
    var things = Application('com.culturedcode.ThingsMac');
    if (!things.running()) return JSON.stringify({status:'unavailable'});
    var id = argv[0];
    var item = things.toDos.byId(id);
    if (!item.exists()) return JSON.stringify({status:'deleted'});
    if (things.lists.byId('TMTrashListSource').toDos.byId(id).exists()) return JSON.stringify({status:'deleted'});
    var status = String(item.status());
    var endedAt = null;
    if (status === 'completed' || status === 'canceled') {
        try {
            var date = status === 'completed' ? item.completionDate() : item.cancellationDate();
            if (date && date.getTime) endedAt = date.getTime() / 1000;
        } catch (_) {}
    }
    return JSON.stringify({status:status, ended_at:endedAt, name:item.name()});
}
