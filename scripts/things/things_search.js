function searchURL(title) {
    return 'https://kagi.com/search?q=' + encodeURIComponent(title);
}
function run(argv) {
    var titles = JSON.parse(argv[0]).filter(function(t) { return typeof t === 'string' && t.trim().length > 0; });
    if (!titles.length) throw Error('No task titles to search');
    var safari = Application('com.apple.Safari');
    var background = titles.length > 1;
    var first = 0;
    var win;
    if (!safari.windows.length) {
        safari.Document({url: searchURL(titles[0])}).make();
        first = 1;
    }
    win = safari.windows[0];
    var original = win.currentTab();
    var added;
    for (var i = first; i < titles.length; i++) {
        added = safari.Tab({url: searchURL(titles[i])});
        win.tabs.push(added);
    }
    if (background) {
        win.currentTab = original;
    } else {
        if (added) win.currentTab = added;
        safari.activate();
    }
    return String(titles.length);
}
if (typeof module !== 'undefined') module.exports = {searchURL: searchURL};
