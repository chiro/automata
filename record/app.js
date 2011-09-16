var init = function(id) {
    var apiMaster = api('master', { year: true, token: true });
    var apiUser   = api('user', { type: 'status', status: 'record', log: 1 });
    var apiScheme = api('scheme', { record: true });
    var apiTempl  = api('template', { type: 'record', links: true });

    var persistent = {};

    with (GNN.UI) {

        var div = GNN.UI.$(id);

        var showRecord = function(json) {
            removeAllChildren(div);

            // textify function specific to the field
            var toText = function(obj, klass, record) {
                if (/^optional/.test(klass)) {
                    if (obj == null) return '';
                    if (obj.length == 0) return '0';
                    var a = $new('a', {
                        attr: { href: '.' },
                        child: obj.length+''
                    });
                    var show = false;
                    new Observer(a, 'onclick', function(e) {
                        e.stop();
                        var elem = e.event.element;
                        removeAllChildren(a);
                        if (show) {
                            a.appendChild($text(obj.length));
                        } else {
                            a.appendChild($text(obj.join(', ')));
                        }
                        show = !show;
                    });
                    return a;
                }

                switch (klass) {
                case 'status':
                    if (obj == null) return '';
                    if (typeof obj == 'boolean' && obj) obj = 'OK';
                    switch (obj) {
                    case 'OK': return '提出済';
                    case 'NG': return '要再提出';
                    case 'build': /* pass through */
                    case 'check': return '確認中';
                    case 'build:NG': return '要再提出';
                    case 'check:NG': return '提出済';
                    }
                    return '';
                case 'unsolved':
                    if (obj == null) return '';
                    return obj.map(function(x) {
                        if (x[1] == 1) {
                            return x[0];
                        } else {
                            return x[0] + 'のうち残り' + x[1] + '問';
                        }
                    }).join(', ');
                case 'test':
                    if (record.log && record.log.test) {
                        var t = record.log.test;
                        if (t.passed == t.number) {
                            return t.passed+'/'+t.number;
                        } else {
                            return $new('span', { child: [
                                $new('em', { child: t.passed }),
                                '/'+t.number
                            ] });
                        }
                    }
                    return '';
                default:
                    return obj;
                }
            };

            // records
            (json.scheme||[]).forEach(function(sc) { // for each report
                var pers = persistent[sc.id] || {};
                persistent[sc.id] = pers;

                var table = $new('table', {
                    id: sc.id,
                    attr: { summary: sc.id },
                    child: $new('tr', { child: sc.record.map(function(col) {
                        return $new('th', {
                            klass: col.field,
                            child: col.label
                        });
                    }) })
                });

                var logView = new LogView(sc.id, json.user);
                var solvedList = new SolvedView(sc.id, json.user);
                var testResult = new TestResultView(sc.id);
                var fileBrowser = new FileBrowserView(sc.id);
                var tabs = [ logView, solvedList ];
                if (sc.record.some(function(col){return col.field=='test';})) {
                    tabs.push(testResult);
                }
                tabs.push(fileBrowser);
                var status = new StatusWindow(sc.id, tabs);

                var makeStatusId = function(x) {
                    return [ x, sc.id, 'status' ].filter(function(x) {
                        return !!x;
                    }).join('-');
                };

                var updateSelectedRow = function() {
                    var getParent = function(e) {
                        return e.parentNode.parentNode;
                    };

                    $select({
                        tag: 'a', klass: makeStatusId()
                    }).forEach(function(e) {
                        removeClass(getParent(e), 'selected');
                    });
                    status.hide();

                    var id = pers.selected;
                    if (!id) return;

                    if (json.user.length > 1) { // highlight
                        var elem = $(makeStatusId(pers.selected));
                        if (elem) {
                            var parent = getParent(elem);
                            appendClass(parent, 'selected');
                            status.show(id, 'log');
                        }
                    } else {
                        status.show(id, 'log');
                    }
                };

                (json.user||[]).forEach(function(student) { // for each student
                    var tr = $new('tr');
                    var id = student.token;
                    var record = (student.report||{})[sc.id]||{};
                    var autoUpdate;

                    var makeStatusNode = function(text) {
                        if (json.user.length == 1) {
                            pers.selected = student.token;
                        } else if (json.user.length > 1) {
                            if (typeof pers.selected == 'undefined') {
                                pers.selected = (json.master||{}).token;
                            }

                            var klass = makeStatusId();
                            text = $new('a', {
                                id: makeStatusId(id),
                                klass: klass,
                                attr: { href: '.' },
                                child: text
                            });
                            new Observer(text, 'onclick', function(e) {
                                e.stop();
                                if (pers.selected == id) {
                                    pers.selected = null;
                                } else {
                                    pers.selected = id;
                                }
                                updateSelectedRow();
                            });
                        }
                        return text;
                    };

                    sc.record.forEach(function(col) {
                        var td = $new('td', { klass: col.field });
                        tr.appendChild(td);

                        var fld = student[col.field];
                        fld = fld || record[col.field];
                        var text = toText(fld, col.field, record);

                        if (col.field == 'status') {
                            if (text.length > 0) {
                                text = makeStatusNode(text);
                            }
                            if (fld == 'check' && sc.update == 'auto') {
                                autoUpdate = true;
                                td.appendChild(loadingIcon());
                            }
                            if ((fld||'').length > 0) {
                                fld = fld.replace(/[^0-9a-zA-Z]/g, '-');
                                appendClass(td, fld);
                            }
                        }

                        td.appendChild($node(text));
                    });

                    if (autoUpdate) {
                        var updateRecord = function() {
                            GNN.JSONP.retrieve({
                                user: apiUser.refresh()
                            }, function(json2) {
                                json2.master = json.master;
                                json2.scheme = json.scheme;
                                showRecord(json2);
                            });
                        };
                        setTimeout(updateRecord, 2000);
                    }
                    table.appendChild(tr);
                });
                div.appendChild(table);
                div.appendChild(status.window);

                updateSelectedRow();
            });
        };

        async = {
            template: function(json) {
                // fill page template
                setTitle(json.template);
                addLinks(json.template.links);
            },
            master: showRecord,
            user: {
                keys: 'user scheme'.split(' '),
                callback: showRecord
            },
            scheme: showRecord
        };

        GNN.JSONP.retrieve({
            master:   apiMaster,
            user:     apiUser,
            scheme:   apiScheme,
            template: apiTempl,
            async: async
        }, null, jsonpFailure);
    }
};
